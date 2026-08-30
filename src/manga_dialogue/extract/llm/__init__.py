from manga_dialogue.extract.llm.base import ImagePart, ParseError, Part, Refused, TextPart, TransientError, VisionModel

PROVIDER_PREFIXES = {
    "claude-": "anthropic",
    "gemini-": "gemini",
}


def provider_for(model: str) -> str:
    for prefix, provider in PROVIDER_PREFIXES.items():
        if model.startswith(prefix):
            return provider
    raise ValueError(f"モデル名からプロバイダを判定できません: {model}（claude-* / gemini-*）")


def get_model(model: str) -> VisionModel:
    """モデル ID の接頭辞からプロバイダを選び、クライアントを生成する"""
    provider = provider_for(model)
    if provider == "anthropic":
        from manga_dialogue.extract.llm.anthropic_model import AnthropicModel

        return AnthropicModel(model)
    from manga_dialogue.extract.llm.gemini_model import GeminiModel

    return GeminiModel(model)


__all__ = [
    "ImagePart", "ParseError", "Part", "Refused", "TextPart", "TransientError", "VisionModel",
    "get_model", "provider_for",
]
