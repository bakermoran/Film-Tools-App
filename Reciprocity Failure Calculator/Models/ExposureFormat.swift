//
//  ExposureFormat.swift
//  Reciprocity Failure Calculator
//

import Foundation

enum ExposureFormat {
    /// Parses the ways people write shutter times, returning seconds.
    /// Accepts `30`, `0.5`, `1/4`, `30s`, `2m`, `2m30s`, `1h5m`, `1:30`, `1:02:30`.
    static func parse(_ input: String) -> Double? {
        let text = input.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty else { return nil }

        let seconds: Double?
        if text.contains("/") {
            seconds = parseFraction(text.hasSuffix("s") ? String(text.dropLast()) : text)
        } else if text.contains(":") {
            seconds = parseClock(text)
        } else if text.contains(where: { "hms".contains($0) }) {
            seconds = parseUnits(text)
        } else {
            seconds = Double(text)
        }

        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private static func parseFraction(_ text: String) -> Double? {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0
        else { return nil }
        return n / d
    }

    /// `m:ss` or `h:mm:ss`
    private static func parseClock(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }

    /// e.g. `1h5m`, `2m30s`, `45s`
    private static func parseUnits(_ text: String) -> Double? {
        var total = 0.0
        var number = ""
        var seenUnits = Set<Character>()
        for ch in text {
            if ch.isNumber || ch == "." {
                number.append(ch)
            } else if let multiplier = ["h": 3600.0, "m": 60, "s": 1][ch] {
                guard let value = Double(number), !seenUnits.contains(ch) else { return nil }
                seenUnits.insert(ch)
                total += value * multiplier
                number = ""
            } else {
                return nil
            }
        }
        // A trailing bare number is seconds, so `2m30` means 2m30s.
        if !number.isEmpty {
            guard let value = Double(number), !seenUnits.contains("s") else { return nil }
            total += value
        }
        return total
    }

    /// Short human-readable duration: `1/250 s`, `0.7 s`, `12 s`, `2m 14s`, `1h 03m 20s`.
    static func string(fromSeconds seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }

        if seconds < 1 {
            let denominator = (1 / seconds).rounded()
            // Show as a shutter fraction when it is one (within 2%).
            if denominator >= 2, abs(1 / denominator - seconds) / seconds < 0.02 {
                return "1/\(Int(denominator)) s"
            }
            return String(format: "%.1f s", seconds)
        }
        if seconds < 10 {
            let text = String(format: "%.1f", seconds)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + " s"
        }

        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, s) }
        return String(format: "%dm %02ds", m, s)
    }

    /// Countdown display: `0:42`, `12:05`, `1:02:09`.
    static func clock(fromSeconds seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// `+1.3 stops`, `+1 stop`, `no change`
    static func stops(_ stops: Double) -> String {
        let rounded = (stops * 10).rounded() / 10
        if rounded <= 0 { return String(localized: "no change") }
        let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return rounded == 1 ? String(localized: "+\(number) stop") : String(localized: "+\(number) stops")
    }
}
