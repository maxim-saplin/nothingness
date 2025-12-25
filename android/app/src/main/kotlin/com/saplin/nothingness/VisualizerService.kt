package com.saplin.nothingness

import android.media.audiofx.Visualizer
import android.util.Log
import kotlin.math.log10

class VisualizerService {
    companion object {
        private const val TAG = "VisualizerService"
        private const val MAX_BARS = 32
        
        // Default settings
        private const val DEFAULT_NOISE_GATE_DB = -45.0
        private const val DEFAULT_NUM_BARS = 12
        private const val DEFAULT_FALL_SMOOTHING = 0.12
        
        private const val MIN_MAGNITUDE = 2.0 // Lower threshold for 8-bit data
        private const val RISE_SMOOTHING = 0.9
        private const val GAIN_BOOST_DB = 6.0
    }

    private var visualizer: Visualizer? = null
    private var spectrumCallback: ((List<Double>) -> Unit)? = null
    
    @Volatile private var noiseGateDb: Double = DEFAULT_NOISE_GATE_DB
    @Volatile private var numBars: Int = DEFAULT_NUM_BARS
    @Volatile private var fallSmoothing: Double = DEFAULT_FALL_SMOOTHING
    
    private val barValues = DoubleArray(MAX_BARS)

    fun updateSettings(newNoiseGateDb: Double, newNumBars: Int, newDecaySpeed: Double) {
        noiseGateDb = newNoiseGateDb
        numBars = newNumBars.coerceIn(8, MAX_BARS)
        fallSmoothing = newDecaySpeed.coerceIn(0.01, 0.5)
    }

    fun startCapture(sessionId: Int, callback: (List<Double>) -> Unit): Boolean {
        stopCapture()
        spectrumCallback = callback
        
        try {
            visualizer = Visualizer(sessionId)
            visualizer?.captureSize = Visualizer.getCaptureSizeRange()[1] // Max size
            
            visualizer?.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(visualizer: Visualizer?, waveform: ByteArray?, samplingRate: Int) {
                }

                override fun onFftDataCapture(visualizer: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                    if (fft != null) {
                        processFft(fft, samplingRate)
                    }
                }
            }, Visualizer.getMaxCaptureRate(), false, true)
            
            visualizer?.enabled = true
            Log.d(TAG, "Visualizer started for session $sessionId")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error starting visualizer: $e")
            return false
        }
    }

    fun stopCapture() {
        try {
            visualizer?.enabled = false
        } catch (e: Exception) {
            // Ignore
        }
        visualizer?.release()
        visualizer = null
        spectrumCallback = null
    }

    private fun processFft(fft: ByteArray, samplingRate: Int) {
        val n = fft.size
        val magnitudes = DoubleArray(n / 2)
        
        // Calculate magnitudes
        // byte[0] is real part of 0Hz
        magnitudes[0] = Math.abs(fft[0].toDouble())
        
        for (k in 1 until n / 2) {
            val real = fft[2 * k].toDouble()
            val imag = fft[2 * k + 1].toDouble()
            magnitudes[k] = Math.hypot(real, imag)
        }
        
        calculateBars(magnitudes, samplingRate)
        
        spectrumCallback?.invoke(barValues.take(numBars))
    }
    
    private fun calculateBars(magnitudes: DoubleArray, samplingRate: Int) {
        val fftSize = magnitudes.size * 2
        val nyquist = samplingRate / 2000 // samplingRate is in mHz? No, usually Hz. Visualizer doc says mHz.
        // Wait, samplingRate in onFftDataCapture is in mHz (milliHertz)?
        // Docs say: "samplingRate - the sampling rate of the visualized audio stream"
        // Usually it's 44100000 for 44.1kHz?
        // Let's assume standard Hz for calculation or check docs.
        // Visualizer.getMaxCaptureRate() returns mHz.
        // But samplingRate passed to callback?
        // Let's assume it's consistent.
        
        // Actually, let's just assume 44100 Hz if we can't be sure, or use the value.
        // If it's mHz, we divide by 1000.
        val rateHz = if (samplingRate > 1000000) samplingRate / 1000 else samplingRate
        
        val binWidth = (rateHz / 2.0) / (fftSize / 2)
        
        val minFreq = 80.0
        val maxFreq = 12000.0
        
        val currentNumBars = numBars
        val currentNoiseGate = noiseGateDb
        val currentFallSmoothing = fallSmoothing
        
        for (bar in 0 until currentNumBars) {
            val lowFreq = minFreq * Math.pow(maxFreq / minFreq, bar.toDouble() / currentNumBars)
            val highFreq = minFreq * Math.pow(maxFreq / minFreq, (bar + 1).toDouble() / currentNumBars)
            
            val lowBin = (lowFreq / binWidth).toInt().coerceIn(0, magnitudes.size - 1)
            val highBin = (highFreq / binWidth).toInt().coerceIn(lowBin + 1, magnitudes.size)
            
            var peakMagnitude = 0.0
            for (bin in lowBin until highBin) {
                if (bin < magnitudes.size && magnitudes[bin] > peakMagnitude) {
                    peakMagnitude = magnitudes[bin]
                }
            }
            
            val freqFactor = 1.0 + (1.0 - bar.toDouble() / currentNumBars) * 2.0
            val adjustedMinMagnitude = MIN_MAGNITUDE * freqFactor
            if (peakMagnitude < adjustedMinMagnitude) {
                peakMagnitude = 0.0
            }
            
            // Visualizer returns 8-bit values (approx -128 to 127). Magnitude max is approx 128*sqrt(2) ~ 181?
            // Actually, the values are signed bytes.
            // Reference for dB: 128.0?
            
            val db = if (peakMagnitude > 0.0) {
                20 * log10(peakMagnitude / 128.0) + GAIN_BOOST_DB
            } else {
                -96.0
            }
            
            val lowFreqGateBoost = (currentNumBars - bar) * 0.5
            val thresholdDb = currentNoiseGate + lowFreqGateBoost
            
            if (db <= thresholdDb) {
                barValues[bar] = barValues[bar] * (1.0 - currentFallSmoothing).coerceIn(0.0, 1.0)
                if (barValues[bar] < 0.02) {
                    barValues[bar] = 0.0
                }
                continue
            }
            
            val dynamicRangeDb = 50.0
            val normalized = ((db - thresholdDb) / dynamicRangeDb).coerceIn(0.0, 1.0)
            
            val currentValue = barValues[bar]
            barValues[bar] = if (normalized > currentValue) {
                currentValue + (normalized - currentValue) * RISE_SMOOTHING
            } else {
                currentValue + (normalized - currentValue) * currentFallSmoothing
            }
            
            if (barValues[bar] < 0.05) {
                barValues[bar] = 0.0
            }
        }
    }
}
