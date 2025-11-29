package com.example.nothingness

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import androidx.core.content.ContextCompat
import kotlin.math.log10
import kotlin.math.sqrt

class AudioCaptureService(private val context: Context) {
    
    companion object {
        private const val TAG = "AudioCaptureService"
        private const val SAMPLE_RATE = 44100
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val FFT_SIZE = 1024
        private const val MAX_BARS = 32  // Maximum possible bars
        
        // Default settings
        private const val DEFAULT_NOISE_GATE_DB = -35.0
        private const val DEFAULT_NUM_BARS = 12
        private const val DEFAULT_FALL_SMOOTHING = 0.12
        
        // Minimum magnitude to consider (filters out mic noise floor).
        // NOTE: After FFT normalization, typical per-bin magnitudes are much smaller,
        // so this value must be low – otherwise even loud signals get cut.
        private const val MIN_MAGNITUDE = 5.0
        // Smoothing factor for rise
        private const val RISE_SMOOTHING = 0.5  // How fast bars rise
        
        // Gain boost in dB to apply before gating.
        // Lifts quiet mic signals up so typical slider ranges (-60 to -20) work better.
        // +24 dB corresponds to approx 15.8x amplitude boost.
        private const val GAIN_BOOST_DB = 24.0
    }
    
    private var audioRecord: AudioRecord? = null
    private var isCapturing = false
    private var captureThread: Thread? = null
    private var spectrumCallback: ((List<Double>) -> Unit)? = null
    
    // Configurable settings
    @Volatile private var noiseGateDb: Double = DEFAULT_NOISE_GATE_DB
    @Volatile private var numBars: Int = DEFAULT_NUM_BARS
    @Volatile private var fallSmoothing: Double = DEFAULT_FALL_SMOOTHING
    
    // Pre-allocated arrays for FFT
    private val audioBuffer = ShortArray(FFT_SIZE)
    private val fftReal = DoubleArray(FFT_SIZE)
    private val fftImag = DoubleArray(FFT_SIZE)
    private val magnitudes = DoubleArray(FFT_SIZE / 2)
    private val barValues = DoubleArray(MAX_BARS)
    
    fun updateSettings(newNoiseGateDb: Double, newNumBars: Int, newDecaySpeed: Double) {
        noiseGateDb = newNoiseGateDb
        numBars = newNumBars.coerceIn(8, MAX_BARS)
        fallSmoothing = newDecaySpeed.coerceIn(0.01, 0.5)
        Log.d(TAG, "Settings updated: noiseGate=$noiseGateDb, bars=$numBars, decay=$fallSmoothing")
    }
    
    fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    fun startCapture(callback: (List<Double>) -> Unit): Boolean {
        if (!hasPermission()) {
            Log.e(TAG, "Missing RECORD_AUDIO permission")
            return false
        }
        
        if (isCapturing) {
            Log.w(TAG, "Already capturing")
            return true
        }
        
        spectrumCallback = callback
        
        val minBufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        val bufferSize = maxOf(minBufferSize, FFT_SIZE * 2)
        
        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize
            )
            
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "Failed to initialize AudioRecord")
                audioRecord?.release()
                audioRecord = null
                return false
            }
            
            audioRecord?.startRecording()
            isCapturing = true
            
            captureThread = Thread {
                captureLoop()
            }.apply {
                priority = Thread.MAX_PRIORITY
                start()
            }
            
            Log.d(TAG, "Audio capture started")
            return true
            
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception starting audio capture", e)
            return false
        }
    }
    
    fun stopCapture() {
        isCapturing = false
        captureThread?.interrupt()
        captureThread = null
        
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
        
        spectrumCallback = null
        Log.d(TAG, "Audio capture stopped")
    }
    
    private fun captureLoop() {
        while (isCapturing && !Thread.interrupted()) {
            val readResult = audioRecord?.read(audioBuffer, 0, FFT_SIZE) ?: -1
            
            if (readResult > 0) {
                // Convert to double and apply Hamming window
                for (i in 0 until FFT_SIZE) {
                    val window = 0.54 - 0.46 * kotlin.math.cos(2.0 * Math.PI * i / (FFT_SIZE - 1))
                    fftReal[i] = audioBuffer[i].toDouble() * window
                    fftImag[i] = 0.0
                }
                
                // Perform FFT
                fft(fftReal, fftImag)
                
                // Calculate magnitudes (only first half is meaningful)
                for (i in 0 until FFT_SIZE / 2) {
                    val real = fftReal[i]
                    val imag = fftImag[i]
                    // Normalize FFT output by dividing by FFT_SIZE to get back to sample amplitude range
                    magnitudes[i] = sqrt(real * real + imag * imag) * 2.0 / FFT_SIZE
                }
                
                // Group into bars with logarithmic frequency scaling
                calculateBars()
                
                // Send only the configured number of bars to callback
                spectrumCallback?.invoke(barValues.take(numBars))
            }
            
            // Target ~30fps
            try {
                Thread.sleep(33)
            } catch (e: InterruptedException) {
                break
            }
        }
    }
    
    private fun calculateBars() {
        // Use logarithmic scaling for frequency bins
        val nyquist = SAMPLE_RATE / 2
        val binWidth = nyquist.toDouble() / (FFT_SIZE / 2)
        
        // Frequency range: skip very low frequencies which pick up room rumble/noise
        val minFreq = 80.0
        val maxFreq = 12000.0
        
        // Use current configurable settings
        val currentNumBars = numBars
        val currentNoiseGate = noiseGateDb
        val currentFallSmoothing = fallSmoothing
        
        for (bar in 0 until currentNumBars) {
            // Logarithmic frequency mapping
            val lowFreq = minFreq * Math.pow(maxFreq / minFreq, bar.toDouble() / currentNumBars)
            val highFreq = minFreq * Math.pow(maxFreq / minFreq, (bar + 1).toDouble() / currentNumBars)
            
            val lowBin = (lowFreq / binWidth).toInt().coerceIn(0, FFT_SIZE / 2 - 1)
            val highBin = (highFreq / binWidth).toInt().coerceIn(lowBin + 1, FFT_SIZE / 2)
            
            // Find peak magnitude in this frequency range
            var peakMagnitude = 0.0
            for (bin in lowBin until highBin) {
                if (magnitudes[bin] > peakMagnitude) {
                    peakMagnitude = magnitudes[bin]
                }
            }
            
            // Apply frequency-dependent noise floor: low freqs need higher threshold
            val freqFactor = 1.0 + (1.0 - bar.toDouble() / currentNumBars) * 2.0  // 3x for lowest, 1x for highest
            val adjustedMinMagnitude = MIN_MAGNITUDE * freqFactor
            if (peakMagnitude < adjustedMinMagnitude) {
                peakMagnitude = 0.0
            }
            
            // Convert to dB scale (reference 32768.0 for 16-bit signed audio)
            // Apply GAIN_BOOST_DB here to shift signals into a more usable range
            val db = if (peakMagnitude > 0.0) {
                20 * log10(peakMagnitude / 32768.0) + GAIN_BOOST_DB
            } else {
                -96.0
            }
            
            // Noise gate in dB domain:
            // - Base threshold from slider (noiseGateDb)
            // - Extra boost for low freqs to suppress rumble
            val lowFreqGateBoost = (currentNumBars - bar) * 0.5  // up to +12 dB on lowest bar for 24 bars
            val thresholdDb = currentNoiseGate + lowFreqGateBoost
            
            if (db <= thresholdDb) {
                // Below threshold -> fully muted for this frame
                barValues[bar] = barValues[bar] * (1.0 - currentFallSmoothing).coerceIn(0.0, 1.0)
                if (barValues[bar] < 0.02) {
                    barValues[bar] = 0.0
                }
                continue
            }
            
            // Map a fixed dynamic range above the threshold to 0..1
            // This keeps bars responsive even if overall level is low.
            val dynamicRangeDb = 22.0  // ~22 dB from just above threshold to full scale
            val normalized = ((db - thresholdDb) / dynamicRangeDb).coerceIn(0.0, 1.0)
            
            // Apply asymmetric smoothing (fast attack, configurable decay)
            val currentValue = barValues[bar]
            barValues[bar] = if (normalized > currentValue) {
                // Rising: faster response
                currentValue + (normalized - currentValue) * RISE_SMOOTHING
            } else {
                // Falling: configurable decay speed
                currentValue + (normalized - currentValue) * currentFallSmoothing
            }
            
            // Apply final threshold to eliminate residual noise (5% threshold)
            if (barValues[bar] < 0.05) {
                barValues[bar] = 0.0
            }
        }
    }
    
    // Cooley-Tukey FFT (in-place, radix-2)
    private fun fft(real: DoubleArray, imag: DoubleArray) {
        val n = real.size
        
        // Bit reversal
        var j = 0
        for (i in 0 until n - 1) {
            if (i < j) {
                var temp = real[i]
                real[i] = real[j]
                real[j] = temp
                temp = imag[i]
                imag[i] = imag[j]
                imag[j] = temp
            }
            var k = n / 2
            while (k <= j) {
                j -= k
                k /= 2
            }
            j += k
        }
        
        // FFT
        var len = 2
        while (len <= n) {
            val halfLen = len / 2
            val angle = -2.0 * Math.PI / len
            val wReal = kotlin.math.cos(angle)
            val wImag = kotlin.math.sin(angle)
            
            var i = 0
            while (i < n) {
                var wpReal = 1.0
                var wpImag = 0.0
                
                for (m in 0 until halfLen) {
                    val idx1 = i + m
                    val idx2 = i + m + halfLen
                    
                    val tReal = wpReal * real[idx2] - wpImag * imag[idx2]
                    val tImag = wpReal * imag[idx2] + wpImag * real[idx2]
                    
                    real[idx2] = real[idx1] - tReal
                    imag[idx2] = imag[idx1] - tImag
                    real[idx1] = real[idx1] + tReal
                    imag[idx1] = imag[idx1] + tImag
                    
                    val newWpReal = wpReal * wReal - wpImag * wImag
                    wpImag = wpReal * wImag + wpImag * wReal
                    wpReal = newWpReal
                }
                
                i += len
            }
            
            len *= 2
        }
    }
}

