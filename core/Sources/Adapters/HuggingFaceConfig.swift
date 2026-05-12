import Foundation

public enum HuggingFaceConfig {
    public static let chatCompletionsURL = URL(string: "https://router.huggingface.co/v1/chat/completions")!

    // OAuth-only allowlist. Keep this curated to models that behave well for translation.
    public static let providers: [TranslationProvider] = [
        TranslationProvider(
            id: "meta-llama/Meta-Llama-3.1-70B-Instruct",
            displayName: "Llama 3.1 70B",
            qualities: [.Optimal]
        ),
        TranslationProvider(
            id: "Qwen/Qwen3-235B-A22B-Instruct-2507-FP8",
            displayName: "Qwen/Qwen/Qwen3-235B-A22B-Instruct-2507-FP8",
            qualities: [.Optimal]
        ),
        TranslationProvider(
            id: "Qwen/Qwen2.5-72B-Instruct",
            displayName: "Qwen 2.5 72B",
            qualities: [.Optimal]
        ),
        TranslationProvider(
            id: "google/gemma-2-27b-it",
            displayName: "Gemma 2 27B",
            qualities: [.Optimal]
        ),
    ]
}
