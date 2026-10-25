#include "AudioStats.h"

#include <stdexcept>

EWMA::EWMA() : m_output(InitialOutput), m_alpha(DefaultAlpha) {}

EWMA::EWMA(double alpha) : m_output(InitialOutput), m_alpha(alpha) {
    if (alpha < 0.0 || alpha > 1.0) {
        throw std::invalid_argument("alpha must be between 0 and 1");
    }
}

double EWMA::addSample(double input) {
    if (m_output == InitialOutput) {
        m_output = input;
    }
    else {
        m_output = m_alpha * (input - m_output) + m_output;
    }
    return m_output;
}

double EWMA::getOutput() const {
    if (m_output == InitialOutput) {
        throw std::logic_error("EWMA is uninitialized: no input has been provided");
    }
    return m_output;
}

#include "AudioStatsMath.h"

double AudioStatsKbps(double bytes, double seconds) {
    if (!(seconds >= AUDIO_STATS_MIN_WINDOW) || bytes < 0) {
        return -1;
    }
    return bytes * 8.0 / 1000.0 / seconds;
}

double AudioStatsMeanMs(double totalMs, int packets) {
    return packets > 0 ? totalMs / packets : -1;
}
