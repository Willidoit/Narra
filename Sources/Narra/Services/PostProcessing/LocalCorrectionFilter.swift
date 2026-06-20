import Foundation

public struct LocalCorrectionFilter: Sendable {
    public init() {}

    // MARK: - Public Interface

    public func apply(_ request: PostProcessingRequest) -> PostProcessingResult {
        let trimmedText = request.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedText = Self.cleanedText(from: trimmedText, confidence: request.segment?.confidence)
        let cleanedSegment = Self.makeSegment(from: request.segment, text: cleanedText)

        guard !cleanedText.isEmpty else {
            return PostProcessingResult(
                refinedText: request.context.map(\.text).joined(separator: " "),
                segments: request.context
            )
        }

        if Self.hasCorrectionPrefix(in: trimmedText) {
            return PostProcessingResult(refinedText: cleanedText, segments: [cleanedSegment])
        }

        if let deduplicated = Self.deduplicatedResult(
            context: request.context,
            current: cleanedSegment,
            cleanedText: cleanedText
        ) {
            return deduplicated
        }

        let combinedSegments = request.context + [cleanedSegment]
        return PostProcessingResult(
            refinedText: combinedSegments.map(\.text).joined(separator: " "),
            segments: combinedSegments
        )
    }

    // MARK: - Correction Prefix Stripping

    private static func cleanedText(from text: String, confidence: Double?) -> String {
        guard !text.isEmpty else { return text }

        let tokenized = tokenize(text)
        let afterMidCorrection = stripMidSentenceCorrection(from: tokenized)
        let withoutPrefix = stripCorrectionPrefix(from: afterMidCorrection)
        let withoutFillers = removeStandaloneFillers(from: withoutPrefix, confidence: confidence)
        return reconstruct(from: withoutFillers)
    }

    private static func hasCorrectionPrefix(in text: String) -> Bool {
        let tokens = tokenize(text)
        return stripCorrectionPrefix(from: tokens).count != tokens.count
    }

    // MARK: - Deduplication

    private static func deduplicatedResult(
        context: [TranscriptSegment],
        current: TranscriptSegment,
        cleanedText: String
    ) -> PostProcessingResult? {
        guard let previous = context.last else {
            return nil
        }

        guard isSubstantiallySame(previous.text, cleanedText) else {
            return nil
        }

        let selected = betterSegment(previous: previous, current: current)
        let mergedSegments = Array(context.dropLast()) + [selected]

        return PostProcessingResult(
            refinedText: mergedSegments.map(\.text).joined(separator: " "),
            segments: mergedSegments
        )
    }

    private static func betterSegment(previous: TranscriptSegment, current: TranscriptSegment) -> TranscriptSegment {
        let previousScore = cleanlinessScore(for: previous.text)
        let currentScore = cleanlinessScore(for: current.text)

        return currentScore >= previousScore ? current : previous
    }

    private static func isSubstantiallySame(_ lhs: String, _ rhs: String) -> Bool {
        let leftTokens = normalizedComparisonTokens(from: lhs)
        let rightTokens = normalizedComparisonTokens(from: rhs)

        guard !leftTokens.isEmpty, !rightTokens.isEmpty else {
            return false
        }

        if leftTokens == rightTokens {
            return true
        }

        let overlap = Set(leftTokens).intersection(rightTokens).count
        let denominator = Double(max(leftTokens.count, rightTokens.count))
        return denominator > 0 && Double(overlap) / denominator >= 0.8
    }

    // MARK: - Scoring

    private static func cleanlinessScore(for text: String) -> Double {
        let tokens = tokenize(text)
        let wordCount = tokens.reduce(into: 0.0) { count, token in
            if case .word = token {
                count += 1
            }
        }

        let perTokenPenalty = tokens.reduce(into: 0.0) { count, token in
            guard case .word(let word) = token else { return }
            switch word.lowercased() {
            case "um", "uh":
                count += 2
            case "like":
                if isLikelyStandaloneLike(originalText: text) {
                    count += 2
                }
            default:
                break
            }
        }

        let youKnowPenalty = Double(standaloneYouKnowCount(in: tokens)) * 2

        return wordCount - perTokenPenalty - youKnowPenalty
    }

    private static func normalizedComparisonTokens(from text: String) -> [String] {
        tokenize(cleanedText(from: text, confidence: nil))
            .compactMap { token in
                guard case .word(let word) = token else { return nil }
                return word.lowercased()
            }
    }

    /// Phrases that, at the start of an utterance, mean "ignore what I was
    /// about to say". Order matters only for ambiguous overlaps; first match
    /// wins. Multi-word patterns try first so "no wait" beats a hypothetical
    /// bare "no".
    private static let correctionPrefixes: [[String]] = [
        ["scratch", "that"],
        ["no", "wait"],
        ["oh", "wait"],
        ["wait", "no"],
        ["or", "rather"],
        ["or", "actually"],
        ["i", "mean"],
        ["i", "meant"],
        ["let", "me", "rephrase"],
        ["let", "me", "restart"],
        ["sorry", "i", "mean"],
        ["sorry", "i", "meant"],
        ["actually"],
        ["rather"],
    ]

    /// Strong markers that mean "throw out everything I just said" wherever
    /// they appear. Conservative on purpose: only phrases that are nearly
    /// always corrections, not casual interjections like a bare "actually".
    private static let midSentenceCorrectionMarkers: [[String]] = [
        ["scratch", "that"],
        ["no", "wait"],
        ["oh", "wait"],
        ["wait", "no"],
        ["let", "me", "rephrase"],
        ["let", "me", "restart"],
    ]

    private static func stripCorrectionPrefix(from tokens: [Token]) -> [Token] {
        guard let firstIndex = firstWordIndex(in: tokens, startingAt: 0) else {
            return tokens
        }

        for pattern in correctionPrefixes {
            if let endIndex = matchedPrefixEndIndex(words: pattern, in: tokens, startingAt: firstIndex) {
                return trimLeadingPunctuation(Array(tokens[endIndex...]))
            }
        }

        return tokens
    }

    /// Find the LAST occurrence of any strong correction marker and drop
    /// everything up to and including it. "I'll head to the store, oh wait,
    /// the mall" → "the mall".
    private static func stripMidSentenceCorrection(from tokens: [Token]) -> [Token] {
        var lastEnd: Int? = nil
        var index = 0
        while index < tokens.count {
            guard case .word = tokens[index] else {
                index += 1
                continue
            }
            var matched = false
            for pattern in midSentenceCorrectionMarkers {
                if let end = matchedPrefixEndIndex(words: pattern, in: tokens, startingAt: index) {
                    lastEnd = end
                    index = end
                    matched = true
                    break
                }
            }
            if !matched {
                index += 1
            }
        }

        if let end = lastEnd, end < tokens.count {
            return trimLeadingPunctuation(Array(tokens[end...]))
        }
        return tokens
    }

    private static func matchedPrefixEndIndex(words: [String], in tokens: [Token], startingAt startIndex: Int) -> Int? {
        var currentIndex = startIndex

        for (position, word) in words.enumerated() {
            guard currentIndex < tokens.count else { return nil }
            guard case .word(let tokenWord) = tokens[currentIndex], tokenWord.lowercased() == word else {
                return nil
            }
            if position == words.count - 1 {
                return currentIndex + 1
            }
            currentIndex = nextWordIndex(after: currentIndex, in: tokens)
        }

        return nil
    }

    private static func nextWordIndex(after index: Int, in tokens: [Token]) -> Int {
        var currentIndex = index + 1

        while currentIndex < tokens.count {
            if case .word = tokens[currentIndex] {
                return currentIndex
            }
            currentIndex += 1
        }

        return tokens.count
    }

    private static func firstWordIndex(in tokens: [Token], startingAt index: Int) -> Int? {
        var currentIndex = index
        while currentIndex < tokens.count {
            if case .word = tokens[currentIndex] {
                return currentIndex
            }
            currentIndex += 1
        }
        return nil
    }

    private static func trimLeadingPunctuation(_ tokens: [Token]) -> [Token] {
        var currentTokens = tokens
        while let first = currentTokens.first, case .punctuation = first {
            currentTokens.removeFirst()
        }
        return currentTokens
    }

    // MARK: - Filler Removal

    private static func removeStandaloneFillers(from tokens: [Token], confidence: Double?) -> [Token] {
        var output: [Token] = []
        var index = 0

        while index < tokens.count {
            switch tokens[index] {
            case .word(let word):
                let lower = word.lowercased()

                if lower == "um" || lower == "uh" {
                    index = skipFillerPunctuation(after: index, in: tokens)
                    continue
                }

                if lower == "you",
                   let knowIndex = nextWordIndexIfMatches("know", after: index, in: tokens),
                   isStandaloneYouKnow(before: output, after: knowIndex, in: tokens) {
                    index = skipFillerPunctuation(after: knowIndex, in: tokens)
                    continue
                }

                if lower == "like",
                   shouldRemoveLike(before: output, at: index, in: tokens, confidence: confidence) {
                    index = skipFillerPunctuation(after: index, in: tokens)
                    continue
                }

                output.append(tokens[index])
                index += 1

            case .punctuation(let punctuation):
                if punctuation == "," && output.isEmpty {
                    index += 1
                    continue
                }

                output.append(tokens[index])
                index += 1
            }
        }

        return output
    }

    private static func skipFillerPunctuation(after index: Int, in tokens: [Token]) -> Int {
        var currentIndex = index + 1
        while currentIndex < tokens.count {
            if case .punctuation(let punctuation) = tokens[currentIndex], punctuation == "," {
                currentIndex += 1
                continue
            }
            break
        }
        return currentIndex
    }

    private static func nextWordIndexIfMatches(_ word: String, after index: Int, in tokens: [Token]) -> Int? {
        var currentIndex = index + 1
        while currentIndex < tokens.count {
            switch tokens[currentIndex] {
            case .word(let candidate):
                return candidate.lowercased() == word ? currentIndex : nil
            case .punctuation:
                currentIndex += 1
            }
        }
        return nil
    }

    private static func isStandaloneYouKnow(before output: [Token], after knowIndex: Int, in tokens: [Token]) -> Bool {
        guard let followingIndex = nextWordOrPunctuationIndex(after: knowIndex, in: tokens) else {
            return true
        }

        if case .punctuation(let punctuation) = tokens[followingIndex], punctuation == "," {
            return true
        }

        return false
    }

    private static func isStandaloneLike(before output: [Token], after index: Int, in tokens: [Token]) -> Bool {
        let atBeginning = output.isEmpty
        let previousWasPunctuation = output.last.map {
            if case .punctuation = $0 {
                return true
            }
            return false
        } ?? false

        guard atBeginning || previousWasPunctuation else {
            return false
        }
        return true
    }

    private static func shouldRemoveLike(before output: [Token], at index: Int, in tokens: [Token], confidence: Double?) -> Bool {
        if isClearlySemanticLike(before: output, at: index, in: tokens) {
            return (confidence ?? 0) < semanticLikeConfidenceThreshold
        }

        return isStandaloneLike(before: output, after: index, in: tokens)
    }

    private static func isLikelyStandaloneLike(originalText: String) -> Bool {
        let lowercasedText = originalText.lowercased()
        return lowercasedText.hasPrefix("like") || lowercasedText.contains(", like") || lowercasedText.contains(" like,")
    }

    private static func isClearlySemanticLike(before output: [Token], at index: Int, in tokens: [Token]) -> Bool {
        guard output.contains(where: { if case .word = $0 { return true } else { return false } }) else {
            return false
        }

        guard let followingIndex = nextWordOrPunctuationIndex(after: index, in: tokens),
              case .word = tokens[followingIndex] else {
            return false
        }

        return true
    }

    private static func nextWordOrPunctuationIndex(after index: Int, in tokens: [Token]) -> Int? {
        let currentIndex = index + 1
        return currentIndex < tokens.count ? currentIndex : nil
    }

    private static let semanticLikeConfidenceThreshold: Double = 0.8

    private static func standaloneYouKnowCount(in tokens: [Token]) -> Int {
        var count = 0
        var index = 0
        while index < tokens.count {
            if case .word(let word) = tokens[index], word.lowercased() == "you",
               let knowIndex = nextWordIndexIfMatches("know", after: index, in: tokens),
               isStandaloneYouKnow(before: [], after: knowIndex, in: tokens) {
                count += 1
                index = knowIndex + 1
            } else {
                index += 1
            }
        }
        return count
    }

    // MARK: - Segment Helpers

    private static func makeSegment(from segment: TranscriptSegment?, text: String) -> TranscriptSegment {
        guard let segment else {
            let now = Date()
            return TranscriptSegment(text: text, startTime: now, endTime: now)
        }

        return TranscriptSegment(
            id: segment.id,
            text: text,
            startTime: segment.startTime,
            endTime: segment.endTime,
            confidence: segment.confidence
        )
    }

    // MARK: - Tokenization

    private static func tokenize(_ text: String) -> [Token] {
        let pattern = #"[A-Za-z]+(?:'[A-Za-z]+)?|\d+|[^\sA-Za-z\d]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [.word(text)]
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.map { match in
            let substring = String(text[Range(match.range, in: text)!])
            if substring.rangeOfCharacter(from: .letters.union(.decimalDigits)) != nil {
                return .word(substring)
            }
            return .punctuation(substring)
        }
    }

    private static func reconstruct(from tokens: [Token]) -> String {
        var result = ""
        var previousWasWord = false

        for token in tokens {
            switch token {
            case .word(let word):
                if !result.isEmpty, !result.hasSuffix(" "), previousWasWord {
                    result.append(" ")
                }
                result.append(word)
                previousWasWord = true

            case .punctuation(let punctuation):
                if punctuation == "," || punctuation == "." || punctuation == "!" || punctuation == "?" || punctuation == ":" || punctuation == ";" {
                    while result.last == " " {
                        result.removeLast()
                    }
                    result.append(punctuation)
                    result.append(" ")
                    previousWasWord = false
                }
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

}

private extension LocalCorrectionFilter {
    enum Token: Equatable {
        case word(String)
        case punctuation(String)
    }
}
