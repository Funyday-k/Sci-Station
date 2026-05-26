import Foundation

public nonisolated enum RecommendationTextSimilarity {
    public static func score(candidateText: String, corpusTexts: [String]) -> Double {
        let candidateVector = termVector(candidateText)
        guard !candidateVector.isEmpty, !corpusTexts.isEmpty else {
            return 0
        }

        let corpusVectors = corpusTexts.map(termVector(_:)).filter { !$0.isEmpty }
        guard !corpusVectors.isEmpty else {
            return 0
        }

        let weights = timeDecayWeights(count: corpusVectors.count)
        let weighted = zip(corpusVectors, weights).reduce(0.0) { partial, pair in
            partial + cosine(candidateVector, pair.0) * pair.1
        }
        return clamp(weighted, lower: 0, upper: 1)
    }

    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        cosine(termVector(lhs), termVector(rhs))
    }

    public static func maxSimilarity(_ text: String, corpusTexts: [String]) -> Double {
        corpusTexts.map { similarity(text, $0) }.max() ?? 0
    }

    public static func meanSimilarity(_ text: String, corpusTexts: [String]) -> Double {
        guard !corpusTexts.isEmpty else {
            return 0
        }
        return corpusTexts.map { similarity(text, $0) }.reduce(0, +) / Double(corpusTexts.count)
    }

    public static func phraseMatch(_ phrase: String, in text: String) -> Double {
        let normalizedPhrase = normalized(phrase)
        let normalizedText = normalized(text)
        guard !normalizedPhrase.isEmpty, !normalizedText.isEmpty else {
            return 0
        }
        if normalizedText.contains(normalizedPhrase) {
            return 1
        }
        let phraseTokens = Set(tokens(normalizedPhrase))
        guard !phraseTokens.isEmpty else {
            return 0
        }
        let textTokens = Set(tokens(normalizedText))
        guard !textTokens.isEmpty else {
            return 0
        }
        return clamp(Double(phraseTokens.intersection(textTokens).count) / Double(phraseTokens.count))
    }

    public static func keywordScore(title: String, abstract: String, keyword: WeightedKeyword) -> Double {
        let titlePhraseMatch = phraseMatch(keyword.text, in: title)
        let abstractPhraseMatch = phraseMatch(keyword.text, in: abstract)
        let tokenCosine = similarity(keyword.text, [title, abstract].joined(separator: " "))
        return clamp(0.5 * titlePhraseMatch + 0.3 * abstractPhraseMatch + 0.2 * tokenCosine)
    }

    public static func weightedKeywordScore(title: String, abstract: String, keywords: [WeightedKeyword]) -> Double? {
        let active = keywords.filter { !$0.text.isEmpty && $0.weight > 0 }
        guard !active.isEmpty else {
            return nil
        }
        let totalWeight = active.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else {
            return nil
        }
        let raw = active.reduce(0.0) { partial, keyword in
            partial + keywordScore(title: title, abstract: abstract, keyword: keyword) * keyword.weight
        }
        return clamp(raw / totalWeight)
    }

    public static func termVector(_ text: String) -> [String: Double] {
        var vector: [String: Double] = [:]
        for token in tokens(text) {
            vector[token, default: 0] += 1
        }
        return vector
    }

    public static func cosine(_ lhs: [String: Double], _ rhs: [String: Double]) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }
        var dot = 0.0
        for (term, value) in lhs {
            dot += value * (rhs[term] ?? 0)
        }
        let lhsNorm = sqrt(lhs.values.reduce(0) { $0 + $1 * $1 })
        let rhsNorm = sqrt(rhs.values.reduce(0) { $0 + $1 * $1 })
        guard lhsNorm > 0, rhsNorm > 0 else {
            return 0
        }
        return dot / (lhsNorm * rhsNorm)
    }

    public static func tokens(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
    }

    public static func normalized(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func timeDecayWeights(count: Int) -> [Double] {
        guard count > 0 else {
            return []
        }
        let raw = (0..<count).map { index in
            1.0 / (1.0 + log10(Double(index) + 1.0))
        }
        let sum = raw.reduce(0, +)
        guard sum > 0 else {
            return Array(repeating: 1.0 / Double(count), count: count)
        }
        return raw.map { $0 / sum }
    }

    public static func clamp(_ value: Double, lower: Double = 0, upper: Double = 1) -> Double {
        min(max(value, lower), upper)
    }
}
