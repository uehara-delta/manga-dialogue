from manga_dialogue.extract.llm.base import ImagePart, ParseError, Part, Refused, TextPart, TransientError, Usage, VisionModel

PROVIDER_PREFIXES = {
    "claude-": "anthropic",
    "gemini-": "gemini",
    "gpt-": "openai",
}

# プロバイダごとの推奨（既定）モデル
PROVIDER_DEFAULT_MODELS = {
    "anthropic": "claude-sonnet-5",
    "gemini": "gemini-3.7-flash",
    "openai": "gpt-5.6-luna",
}


def provider_for(model: str) -> str:
    for prefix, provider in PROVIDER_PREFIXES.items():
        if model.startswith(prefix):
            return provider
    raise ValueError(f"モデル名からプロバイダを判定できません: {model}（claude-* / gemini-* / gpt-*）")


def get_model(model: str) -> VisionModel:
    """モデル ID の接頭辞からプロバイダを選び、クライアントを生成する"""
    provider = provider_for(model)
    if provider == "anthropic":
        from manga_dialogue.extract.llm.anthropic_model import AnthropicModel

        return AnthropicModel(model)
    if provider == "openai":
        from manga_dialogue.extract.llm.openai_model import OpenAIModel

        return OpenAIModel(model)
    from manga_dialogue.extract.llm.gemini_model import GeminiModel

    return GeminiModel(model)


__all__ = [
    "ImagePart", "ParseError", "Part", "Refused", "TextPart", "TransientError", "Usage", "VisionModel",
    "PROVIDER_DEFAULT_MODELS", "get_model", "provider_for",
]
