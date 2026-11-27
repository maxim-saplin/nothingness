#pragma once

#ifndef OPUS_STREAM_H
#define OPUS_STREAM_H

#include "../enums.h"
#include "../soloud/include/soloud.h"

#include <atomic>
#include <cstdint>
#include <mutex>
#include <vector>

// Mirror opus_stream_decoder.h include guards: system opus/ogg on device,
// vendored xiph headers under Emscripten. Everything that actually touches
// opus/ogg is compiled only when xiph is available; a NO_XIPH_LIBS-safe stub
// is provided below so the build still links without xiph.
#if !defined(NO_XIPH_LIBS)
#ifdef __EMSCRIPTEN__
#include "../../xiph/opus/include/opus.h"
#include "../../xiph/ogg/include/ogg/ogg.h"
#else
#include <opus/opus.h>
#include <ogg/ogg.h>
#endif
#endif // !NO_XIPH_LIBS

class Player;
struct ActiveSound;

namespace SoLoud {

#if !defined(NO_XIPH_LIBS)

class OpusStream;

// One decode instance == one playing voice. Each instance is fully
// self-contained: it owns its own OpusDecoder + libogg sync/stream state, a
// read cursor into the parent's immutable compressed bytes, a decoded-PCM
// scratch buffer and a pre-skip counter, so multiple concurrent voices decode
// independently and safely. Decode is lazy/on-demand, driven by getAudio().
class OpusStreamInstance : public AudioSourceInstance {
public:
  OpusStreamInstance(OpusStream *aParent);
  virtual ~OpusStreamInstance();

  virtual unsigned int getAudio(float *aBuffer, unsigned int aSamplesToRead,
                                unsigned int aBufferSize) override;
  virtual result seek(time aSeconds, float *mScratch,
                      unsigned int mScratchSize) override;
  virtual result rewind() override;
  virtual bool hasEnded() override;

private:
  // Decode more compressed data into mPcmScratch until it holds at least
  // [framesWanted] frames or end-of-stream is reached. Returns true if any
  // forward progress (new packet decoded) happened.
  bool fillScratch(int64_t framesWanted);
  // Decode exactly one packet (if available) into mPcmScratch, applying the
  // pending pre-skip. Returns: 1 = packet decoded, 0 = need more bytes,
  // -1 = end of stream.
  int decodeOnePacket();
  // Pull the next compressed chunk from the parent into the ogg sync buffer.
  // Returns the number of bytes fed (0 at end of compressed data).
  size_t feedSync();
  // Re-initialise decoder + ogg state from a given byte offset (used by
  // seek/rewind). Does NOT set the pre-skip counter; caller decides.
  void resetDecodeState(size_t byteOffset);

  OpusStream *mParent;

  OpusDecoder *mDecoder;
  ogg_sync_state mOggSync;
  ogg_stream_state mOggStream;
  bool mStreamInitialized;

  // Read cursor into mParent->mCompressed.
  size_t mByteCursor;

  // Decoded float PCM not yet emitted, interleaved (frame-major). Front is
  // consumed via mPcmConsumed to avoid repeated erase-from-front churn.
  std::vector<float> mPcmScratch;
  size_t mPcmConsumed; // frames already emitted from the front of mPcmScratch

  // Reusable opus_decode_float output scratch (grown on demand, reused).
  std::vector<float> mDecodeScratch;

  // Frames still to discard at the start (pre-skip), in the decoding rate.
  int mSkipPending;

  // Absolute decoded-frame position (output-rate frames already emitted).
  int64_t mDecodedFrameCursor;

  bool mStreamEnded;
};

// Parent audio source. Immutable after load(): all fields are read freely from
// instances on the audio thread. Holds the compressed bytes once, plus a page
// index for fast seeking. No audio decode happens here.
class OpusStream : public AudioSource {
public:
  struct PageEntry {
    int64_t granulepos; // carried (last known) granule for binary search
    size_t byteOffset;  // byte offset of the "OggS" capture pattern
  };

  // The flutter_soloud main [player] instance.
  Player *mThePlayer;
  // The AudioSource this stream belongs to.
  ActiveSound *mParent;

  std::vector<unsigned char> mCompressed;
  int mDecodingSamplerate;
  int mDecodingChannels;
  uint16_t mPreSkip;
  int64_t mTotalFrames;
  long mSerialno;
  size_t mFirstAudioPageOffset;
  std::vector<PageEntry> mPageIndex;

  std::atomic<bool> mIsDestroyed{false};
  // Guards getAudio() against Player::seek/dispose coming from other threads.
  std::mutex mDecodeMutex;

  OpusStream();
  virtual ~OpusStream();

  PlayerErrors load(const unsigned char *mem, int length);
  virtual AudioSourceInstance *createInstance() override;
  time getLength();

  bool isValid() const { return !mIsDestroyed.load(); }
  void markForDestruction() { mIsDestroyed.store(true); }
};

#else // NO_XIPH_LIBS

// Stub so the build links without xiph. load() always fails; nothing can be
// instantiated/decoded. tryLoadOpusBufferStream() is itself guarded by
// NO_XIPH_LIBS in player.cpp, so this stub is never exercised at runtime.
class OpusStream : public AudioSource {
public:
  Player *mThePlayer;
  ActiveSound *mParent;
  std::atomic<bool> mIsDestroyed{false};

  OpusStream() : mThePlayer(nullptr), mParent(nullptr) {}
  virtual ~OpusStream() {}

  PlayerErrors load(const unsigned char *, int) {
    return PlayerErrors::failedToCreateOpusDecoder;
  }
  virtual AudioSourceInstance *createInstance() override { return nullptr; }
  time getLength() { return 0; }

  bool isValid() const { return !mIsDestroyed.load(); }
  void markForDestruction() { mIsDestroyed.store(true); }
};

#endif // !NO_XIPH_LIBS

} // namespace SoLoud

#endif // OPUS_STREAM_H
