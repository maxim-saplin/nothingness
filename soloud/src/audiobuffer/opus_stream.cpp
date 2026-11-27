#if !defined(NO_XIPH_LIBS)

#include "opus_stream.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace SoLoud {

// ---------------------------------------------------------------------------
// Manual Ogg page walk helpers (header-only parsing; no opus_decode here).
// ---------------------------------------------------------------------------

namespace {

// Reads a little-endian uint16 from data[pos..].
static uint16_t readU16LE(const unsigned char *data, size_t pos) {
  return (uint16_t)(data[pos] | (data[pos + 1] << 8));
}

// Reads a little-endian uint32 from data[pos..].
static uint32_t readU32LE(const unsigned char *data, size_t pos) {
  return (uint32_t)(data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) |
                    (data[pos + 3] << 24));
}

// Reads a little-endian int64 (granule position) from data[pos..].
static int64_t readI64LE(const unsigned char *data, size_t pos) {
  uint64_t v = 0;
  for (int i = 0; i < 8; ++i)
    v |= (uint64_t)data[pos + i] << (8 * i);
  return (int64_t)v;
}

// Computes the total on-disk size of the Ogg page starting at [start].
// Returns 0 if the page is malformed/truncated. On success, [payloadSize] is
// the sum of the lacing values and [granule] is the page granule position.
static size_t oggPageSize(const std::vector<unsigned char> &buf, size_t start,
                          size_t &payloadSize, int64_t &granule) {
  // Need at least the 27-byte fixed header.
  if (start + 27 > buf.size())
    return 0;
  if (!(buf[start] == 'O' && buf[start + 1] == 'g' && buf[start + 2] == 'g' &&
        buf[start + 3] == 'S'))
    return 0;

  granule = readI64LE(buf.data(), start + 6);
  const int pageSegments = buf[start + 26];
  if (start + 27 + (size_t)pageSegments > buf.size())
    return 0;

  payloadSize = 0;
  for (int i = 0; i < pageSegments; ++i)
    payloadSize += buf[start + 27 + i];

  const size_t total = 27 + (size_t)pageSegments + payloadSize;
  if (start + total > buf.size())
    return 0;
  return total;
}

} // namespace

// ---------------------------------------------------------------------------
// OpusStream (parent)
// ---------------------------------------------------------------------------

OpusStream::OpusStream()
    : mThePlayer(nullptr), mParent(nullptr), mDecodingSamplerate(48000),
      mDecodingChannels(2), mPreSkip(0), mTotalFrames(0), mSerialno(0),
      mFirstAudioPageOffset(0) {
  // Mirror WavStream's constructor flags: no looping by default; the engine
  // resamples to its own rate. Defaults from AudioSource() are otherwise fine.
  mFlags = 0;
  mBaseSamplerate = 48000;
  mChannels = 2;
}

OpusStream::~OpusStream() { stop(); }

PlayerErrors OpusStream::load(const unsigned char *mem, int length) {
  if (mem == nullptr || length <= 0)
    return PlayerErrors::audioFormatNotSupported;

  // 1. Copy the compressed bytes once. Immutable from here on.
  mCompressed.assign(mem, mem + length);

  // 2 & 3. Walk every Ogg page manually, parsing headers and building the
  // page index. We do NOT rely on ogg_sync's internal byte accounting.
  bool foundHead = false;
  long serialno = 0;
  size_t firstAudioOffset = 0;
  bool firstAudioFound = false;
  int64_t lastGranule = 0;
  int64_t carriedGranule = 0; // last known granule for inherit/unknown pages
  int headerPagesSeen = 0;    // pages belonging to OpusHead/OpusTags

  std::vector<PageEntry> pageIndex;

  size_t offset = 0;
  while (offset < mCompressed.size()) {
    size_t payloadSize = 0;
    int64_t granule = 0;
    size_t pageTotal = oggPageSize(mCompressed, offset, payloadSize, granule);
    if (pageTotal == 0) {
      // Malformed / truncated page. Bail out of header parse if we never even
      // saw OpusHead; otherwise stop walking (treat what we have as the file).
      break;
    }

    const size_t segTableStart = offset + 27;
    const size_t payloadStart = segTableStart + mCompressed[offset + 26];

    // The OpusHead id header lives at the start of the first page's payload.
    if (!foundHead && payloadSize >= 8 &&
        std::memcmp(mCompressed.data() + payloadStart, "OpusHead", 8) == 0) {
      // Parse OpusHead (same layout as opus_stream_decoder.cpp parseOpusHead).
      const unsigned char *h = mCompressed.data() + payloadStart;
      if (payloadSize < 19) {
        return PlayerErrors::audioFormatNotSupported;
      }
      // h[8] = version, h[9] = channels.
      int channels = h[9];
      uint16_t preSkip = readU16LE(h, 10);
      (void)readU32LE(h, 12); // input_sample_rate (informational)

      if (channels <= 0)
        channels = 1;
      if (channels > 2)
        channels = 2;

      mDecodingChannels = channels;
      mPreSkip = preSkip;
      // Opus always decodes at 48 kHz here (ensureDecoder rule).
      mDecodingSamplerate = 48000;
      // The serial number lives at bytes 14..17 (LE) of the Ogg page header.
      serialno = (long)(int32_t)readU32LE(mCompressed.data(), offset + 14);
      foundHead = true;
      headerPagesSeen++;
      // header page granule is 0/ignored; still index it for completeness.
      carriedGranule = (granule >= 0) ? granule : carriedGranule;
      pageIndex.push_back({carriedGranule, offset});
      offset += pageTotal;
      continue;
    }

    if (!foundHead) {
      // Pages before OpusHead (shouldn't happen for a valid Opus file).
      offset += pageTotal;
      continue;
    }

    // OpusTags page (second header). Skip forwarding metadata: the existing
    // whole-file path passes null callbacks, so no behavior loss.
    if (headerPagesSeen == 1 && payloadSize >= 8 &&
        std::memcmp(mCompressed.data() + payloadStart, "OpusTags", 8) == 0) {
      headerPagesSeen++;
      carriedGranule = (granule >= 0) ? granule : carriedGranule;
      pageIndex.push_back({carriedGranule, offset});
      offset += pageTotal;
      continue;
    }

    // From here on, audio data pages.
    if (!firstAudioFound) {
      firstAudioOffset = offset;
      firstAudioFound = true;
    }

    if (granule >= 0) {
      carriedGranule = granule;
      lastGranule = granule;
    }
    // For pages with granule == -1 (no packet completes on the page), carry
    // the previous known granule so binary search stays monotonic.
    pageIndex.push_back({carriedGranule, offset});

    offset += pageTotal;
  }

  if (!foundHead) {
    return PlayerErrors::audioFormatNotSupported;
  }
  if (!firstAudioFound) {
    // No audio pages at all.
    return PlayerErrors::audioFormatNotSupported;
  }

  mSerialno = serialno;
  mFirstAudioPageOffset = firstAudioOffset;
  mPageIndex = std::move(pageIndex);

  // 4. Exact duration from the last page granule (same scaling as the EOS math
  // in opus_stream_decoder.cpp).
  int64_t trimmed = lastGranule - (int64_t)mPreSkip;
  if (trimmed < 0)
    trimmed = 0;
  mTotalFrames =
      (trimmed * (int64_t)mDecodingSamplerate + 47999) / 48000;
  if (mTotalFrames < 0)
    mTotalFrames = 0;

  // Set base class fields for the engine.
  mBaseSamplerate = (float)mDecodingSamplerate;
  mChannels = (unsigned int)mDecodingChannels;

  return PlayerErrors::noError;
}

AudioSourceInstance *OpusStream::createInstance() {
  return new OpusStreamInstance(this);
}

time OpusStream::getLength() {
  if (mBaseSamplerate == 0)
    return 0;
  return (double)mTotalFrames / (double)mBaseSamplerate;
}

// ---------------------------------------------------------------------------
// OpusStreamInstance
// ---------------------------------------------------------------------------

OpusStreamInstance::OpusStreamInstance(OpusStream *aParent)
    : mParent(aParent), mDecoder(nullptr), mStreamInitialized(false),
      mByteCursor(0), mPcmConsumed(0), mSkipPending(0), mDecodedFrameCursor(0),
      mStreamEnded(false) {
  if (mParent == nullptr)
    return;

  mChannels = (unsigned int)mParent->mDecodingChannels;
  mBaseSamplerate = (float)mParent->mDecodingSamplerate;

  int err = OPUS_OK;
  mDecoder = opus_decoder_create(mParent->mDecodingSamplerate,
                                 mParent->mDecodingChannels, &err);
  if (err != OPUS_OK || mDecoder == nullptr) {
    mDecoder = nullptr;
    return;
  }
  opus_decoder_ctl(mDecoder, OPUS_RESET_STATE);

  ogg_sync_init(&mOggSync);

  // Start at the first audio page; pre-skip applies at the true stream start.
  mByteCursor = mParent->mFirstAudioPageOffset;
  mSkipPending = (int)(((int64_t)mParent->mPreSkip *
                            (int64_t)mParent->mDecodingSamplerate +
                        47999) /
                       48000);

  if (ogg_stream_init(&mOggStream, (int)mParent->mSerialno) == 0)
    mStreamInitialized = true;
}

OpusStreamInstance::~OpusStreamInstance() {
  if (mDecoder) {
    opus_decoder_destroy(mDecoder);
    mDecoder = nullptr;
  }
  if (mStreamInitialized) {
    ogg_stream_clear(&mOggStream);
    mStreamInitialized = false;
  }
  ogg_sync_clear(&mOggSync);
}

size_t OpusStreamInstance::feedSync() {
  if (mParent == nullptr)
    return 0;
  const std::vector<unsigned char> &src = mParent->mCompressed;
  if (mByteCursor >= src.size())
    return 0;

  // Pull a small chunk (8-16 KB) of compressed bytes at a time.
  const size_t kChunk = 16 * 1024;
  size_t remaining = src.size() - mByteCursor;
  size_t toFeed = remaining < kChunk ? remaining : kChunk;

  char *oggBuffer = ogg_sync_buffer(&mOggSync, (long)toFeed);
  if (oggBuffer == nullptr)
    return 0;
  std::memcpy(oggBuffer, src.data() + mByteCursor, toFeed);
  ogg_sync_wrote(&mOggSync, (long)toFeed);
  mByteCursor += toFeed;
  return toFeed;
}

int OpusStreamInstance::decodeOnePacket() {
  if (mDecoder == nullptr || !mStreamInitialized)
    return -1;

  ogg_page og;
  ogg_packet op;

  for (;;) {
    // Try to get a packet from the current stream state first.
    int gotPacket = ogg_stream_packetout(&mOggStream, &op);
    if (gotPacket == 1) {
      const int channels = mParent->mDecodingChannels;
      const int samplerate = mParent->mDecodingSamplerate;
      const int maxFrameSize = samplerate * 60 / 1000; // 60 ms
      const size_t needed = (size_t)maxFrameSize * channels;
      if (mDecodeScratch.size() < needed)
        mDecodeScratch.resize(needed);

      int samples = opus_decode_float(mDecoder, op.packet,
                                      (opus_int32)op.bytes,
                                      mDecodeScratch.data(), maxFrameSize, 0);
      if (samples < 0) {
        // Skip invalid packet (mirror opus_stream_decoder.cpp behaviour).
        continue;
      }
      if (samples == 0)
        continue;

      int usableSamples = samples;
      int skippedSamples = 0;
      if (mSkipPending > 0) {
        const int toSkip = std::min(mSkipPending, usableSamples);
        mSkipPending -= toSkip;
        usableSamples -= toSkip;
        skippedSamples = toSkip;
      }
      if (usableSamples <= 0)
        continue;

      const size_t startIndex = (size_t)skippedSamples * channels;
      const size_t floatsToCopy = (size_t)usableSamples * channels;
      mPcmScratch.insert(mPcmScratch.end(),
                         mDecodeScratch.data() + startIndex,
                         mDecodeScratch.data() + startIndex + floatsToCopy);
      return 1;
    }

    // No packet available: pull in the next page.
    int pageRes = ogg_sync_pageout(&mOggSync, &og);
    if (pageRes == 1) {
      // Feed only pages matching our serial (ignore other logical streams).
      if (ogg_page_serialno(&og) == mOggStream.serialno) {
        ogg_stream_pagein(&mOggStream, &og);
      }
      continue;
    }

    // Need more bytes from the compressed buffer.
    if (feedSync() == 0) {
      // No more compressed data: end of stream.
      return -1;
    }
  }
}

bool OpusStreamInstance::fillScratch(int64_t framesWanted) {
  bool progressed = false;
  while ((int64_t)(mPcmScratch.size() / mParent->mDecodingChannels -
                   mPcmConsumed) < framesWanted) {
    int r = decodeOnePacket();
    if (r == 1) {
      progressed = true;
      continue;
    }
    // r == -1: end of stream.
    break;
  }
  return progressed;
}

unsigned int OpusStreamInstance::getAudio(float *aBuffer,
                                          unsigned int aSamplesToRead,
                                          unsigned int aBufferSize) {
  // 1. Parent validity.
  if (mParent == nullptr || !mParent->isValid()) {
    std::memset(aBuffer, 0, sizeof(float) * aSamplesToRead * mChannels);
    return 0;
  }
  if (mDecoder == nullptr) {
    std::memset(aBuffer, 0, sizeof(float) * aSamplesToRead * mChannels);
    return 0;
  }

  // 2. Lock the parent decode mutex (defends vs seek/dispose from threads).
  std::lock_guard<std::mutex> lock(mParent->mDecodeMutex);

  const int channels = mParent->mDecodingChannels;

  // Don't emit past the exact total (end-trim), so the duration matches the
  // whole-file path exactly.
  int64_t framesAllowed = aSamplesToRead;
  if (mParent->mTotalFrames > 0) {
    int64_t remaining = mParent->mTotalFrames - mDecodedFrameCursor;
    if (remaining < 0)
      remaining = 0;
    if (framesAllowed > remaining)
      framesAllowed = remaining;
  }

  // 3. Ensure scratch holds enough decoded frames.
  fillScratch(framesAllowed);

  const int64_t available =
      (int64_t)(mPcmScratch.size() / channels) - (int64_t)mPcmConsumed;
  int64_t framesToEmit = framesAllowed;
  if (framesToEmit > available)
    framesToEmit = available;
  if (framesToEmit < 0)
    framesToEmit = 0;

  // 4. Copy out in planar layout aBuffer[ch*aSamplesToRead + i].
  const float *src = mPcmScratch.data() + (size_t)mPcmConsumed * channels;
  if (channels == 1) {
    if (framesToEmit > 0)
      std::memcpy(aBuffer, src, sizeof(float) * (size_t)framesToEmit);
  } else {
    for (int ch = 0; ch < channels; ++ch) {
      for (int64_t i = 0; i < framesToEmit; ++i) {
        aBuffer[(size_t)ch * aSamplesToRead + (size_t)i] =
            src[(size_t)i * channels + ch];
      }
    }
  }

  // Zero-pad the remainder of the requested block.
  if ((unsigned int)framesToEmit < aSamplesToRead) {
    if (channels == 1) {
      std::memset(aBuffer + framesToEmit, 0,
                  sizeof(float) * (aSamplesToRead - framesToEmit));
    } else {
      for (int ch = 0; ch < channels; ++ch) {
        std::memset(aBuffer + (size_t)ch * aSamplesToRead + framesToEmit, 0,
                    sizeof(float) * (aSamplesToRead - framesToEmit));
      }
    }
  }

  mPcmConsumed += (size_t)framesToEmit;
  mDecodedFrameCursor += framesToEmit;
  mStreamPosition = (double)mDecodedFrameCursor / (double)mBaseSamplerate;

  // Compact the scratch occasionally to keep it small (at most ~one extra
  // packet beyond the request stays buffered).
  if (mPcmConsumed > 0) {
    const size_t consumedFloats = mPcmConsumed * channels;
    if (consumedFloats >= mPcmScratch.size()) {
      mPcmScratch.clear();
      mPcmConsumed = 0;
    } else if (mPcmConsumed > 4096) {
      mPcmScratch.erase(mPcmScratch.begin(),
                        mPcmScratch.begin() + consumedFloats);
      mPcmConsumed = 0;
    }
  }

  // 5. End-of-stream detection + 5ms fade on the final frames.
  // End when we've emitted the authoritative total, or the decoder ran dry
  // (compressed bytes exhausted and scratch couldn't satisfy the request).
  const bool reachedTotal =
      (mParent->mTotalFrames > 0 &&
       mDecodedFrameCursor >= mParent->mTotalFrames);
  const bool ranDry = (mByteCursor >= mParent->mCompressed.size() &&
                       (unsigned int)framesToEmit < aSamplesToRead);
  if (reachedTotal || ranDry) {
    if (!mStreamEnded) {
      mStreamEnded = true;
      // If the decoder ran dry slightly short of the granule-derived total,
      // snap the cursor up so hasEnded() fires reliably (auto-advance).
      if (ranDry && mDecodedFrameCursor < mParent->mTotalFrames)
        mDecodedFrameCursor = mParent->mTotalFrames;
      // Apply 5ms fade-out to the final emitted frames (copied from
      // opus_stream_decoder.cpp:~256-279) so endings match current behavior.
      const size_t fadeSamples = (size_t)(mBaseSamplerate * 0.005); // 5 ms
      if (fadeSamples > 0 && framesToEmit > 0) {
        size_t fadeFrames = fadeSamples;
        if (fadeFrames > (size_t)framesToEmit)
          fadeFrames = (size_t)framesToEmit;
        const size_t startFrame = (size_t)framesToEmit - fadeFrames;
        if (channels == 1) {
          for (size_t i = 0; i < fadeFrames; ++i) {
            float multiplier = 1.0f - (float)i / (float)fadeSamples;
            aBuffer[startFrame + i] *= multiplier;
          }
        } else {
          for (int ch = 0; ch < channels; ++ch) {
            for (size_t i = 0; i < fadeFrames; ++i) {
              float multiplier = 1.0f - (float)i / (float)fadeSamples;
              aBuffer[(size_t)ch * aSamplesToRead + startFrame + i] *=
                  multiplier;
            }
          }
        }
      }
    }
  }

  return (unsigned int)framesToEmit;
}

void OpusStreamInstance::resetDecodeState(size_t byteOffset) {
  if (mDecoder)
    opus_decoder_ctl(mDecoder, OPUS_RESET_STATE);
  ogg_sync_reset(&mOggSync);
  if (mStreamInitialized) {
    ogg_stream_clear(&mOggStream);
    mStreamInitialized = false;
  }
  if (ogg_stream_init(&mOggStream, (int)mParent->mSerialno) == 0)
    mStreamInitialized = true;
  mPcmScratch.clear();
  mPcmConsumed = 0;
  mByteCursor = byteOffset;
}

result OpusStreamInstance::seek(time aSeconds, float *mScratch,
                                unsigned int mScratchSize) {
  (void)mScratch;
  (void)mScratchSize;

  if (mParent == nullptr || !mParent->isValid())
    return INVALID_PARAMETER;
  if (mDecoder == nullptr)
    return INVALID_PARAMETER;

  if (aSeconds <= 0.0)
    return rewind();

  std::lock_guard<std::mutex> lock(mParent->mDecodeMutex);

  // 1. Target frame in the output (decoding) rate.
  int64_t targetFrame =
      (int64_t)std::llround(aSeconds * (double)mBaseSamplerate);
  if (targetFrame < 0)
    targetFrame = 0;
  if (mParent->mTotalFrames > 0 && targetFrame > mParent->mTotalFrames)
    targetFrame = mParent->mTotalFrames;

  // 2. Convert to a 48kHz granule and find a preroll start page.
  const int64_t kPreroll48k = 3840; // 80 ms preroll
  int64_t targetGran48 =
      targetFrame * 48000 / (int64_t)mParent->mDecodingSamplerate +
      (int64_t)mParent->mPreSkip;
  int64_t searchGran = targetGran48 - kPreroll48k;

  // Binary search mPageIndex for the last page with carried granule <=
  // searchGran. Page index is monotonic in carried granule. A page's granule
  // is the position of the LAST sample completing on it, so the audio decoded
  // *from* a chosen page starts at the PREVIOUS page's granule.
  size_t startOffset = mParent->mFirstAudioPageOffset;
  bool startIsStreamStart = true;
  int64_t startGran48 = 0; // 48kHz granule at the START of the chosen page
  {
    const std::vector<OpusStream::PageEntry> &idx = mParent->mPageIndex;
    int lo = 0;
    int hi = (int)idx.size() - 1;
    int best = -1;
    while (lo <= hi) {
      int mid = (lo + hi) / 2;
      if (idx[mid].granulepos <= searchGran) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (best >= 0 && idx[best].byteOffset >= mParent->mFirstAudioPageOffset) {
      startOffset = idx[best].byteOffset;
      // The audio on this page begins at the previous page's granule.
      startGran48 = (best > 0) ? idx[best - 1].granulepos : 0;
      if (startGran48 < 0)
        startGran48 = 0;
    }
    startIsStreamStart = (startOffset == mParent->mFirstAudioPageOffset);
  }

  // 3. Reset decode + ogg state at the chosen start offset.
  resetDecodeState(startOffset);

  // Only re-apply the stream pre-skip when starting at the true stream start;
  // mid-stream granulepos already accounts for pre-skip, so discard purely by
  // frame count to targetFrame.
  if (startIsStreamStart) {
    mSkipPending = (int)(((int64_t)mParent->mPreSkip *
                              (int64_t)mParent->mDecodingSamplerate +
                          47999) /
                         48000);
    mDecodedFrameCursor = 0;
  } else {
    mSkipPending = 0;
    // Seed the absolute frame cursor from the granule at the start of the
    // chosen page (previous page's end granule), converted to output frames.
    int64_t startFrame =
        (startGran48 - (int64_t)mParent->mPreSkip) *
            (int64_t)mParent->mDecodingSamplerate / 48000;
    if (startFrame < 0)
      startFrame = 0;
    mDecodedFrameCursor = startFrame;
  }

  // 4. Decode-discard forward until the decoded position reaches targetFrame.
  const int channels = mParent->mDecodingChannels;
  while (mDecodedFrameCursor < targetFrame) {
    const int64_t haveFrames =
        (int64_t)(mPcmScratch.size() / channels) - (int64_t)mPcmConsumed;
    if (haveFrames <= 0) {
      int r = decodeOnePacket();
      if (r == -1)
        break; // end of stream before target
      continue;
    }
    int64_t need = targetFrame - mDecodedFrameCursor;
    int64_t discard = need < haveFrames ? need : haveFrames;
    mPcmConsumed += (size_t)discard;
    mDecodedFrameCursor += discard;
    // Compact discarded data.
    const size_t consumedFloats = mPcmConsumed * channels;
    if (consumedFloats >= mPcmScratch.size()) {
      mPcmScratch.clear();
      mPcmConsumed = 0;
    } else if (mPcmConsumed > 4096) {
      mPcmScratch.erase(mPcmScratch.begin(),
                        mPcmScratch.begin() + consumedFloats);
      mPcmConsumed = 0;
    }
  }

  // 5. Finalise position.
  mDecodedFrameCursor = targetFrame;
  mStreamPosition = (double)targetFrame / (double)mBaseSamplerate;
  mStreamEnded = (mParent->mTotalFrames > 0 &&
                  targetFrame >= mParent->mTotalFrames);

  return SO_NO_ERROR;
}

result OpusStreamInstance::rewind() {
  if (mParent == nullptr || !mParent->isValid())
    return INVALID_PARAMETER;

  std::lock_guard<std::mutex> lock(mParent->mDecodeMutex);

  resetDecodeState(mParent->mFirstAudioPageOffset);
  mSkipPending = (int)(((int64_t)mParent->mPreSkip *
                            (int64_t)mParent->mDecodingSamplerate +
                        47999) /
                       48000);
  mDecodedFrameCursor = 0;
  mStreamPosition = 0.0;
  mStreamEnded = false;
  return SO_NO_ERROR;
}

bool OpusStreamInstance::hasEnded() {
  if (mParent == nullptr || !mParent->isValid())
    return true;
  if (mStreamEnded && mDecodedFrameCursor >= mParent->mTotalFrames)
    return true;
  return false;
}

} // namespace SoLoud

#endif // !NO_XIPH_LIBS
