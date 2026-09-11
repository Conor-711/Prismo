"""Conservative publication checks, not a claim of semantic translation accuracy."""
import re


def validate_translation(original: str, translated: dict[str, str]) -> bool:
    # Missing numbers and extreme compression usually mean a summary or truncation.
    def numeric_tokens(value):
        value = re.sub(r"https?://\S+", "", value)
        return {token.replace(",", "") for token in re.findall(r"\d+(?:[.,]\d+)*", value)}

    numbers = numeric_tokens(original)
    for language, ratio in (("zh", 0.12), ("en", 0.4)):
        value = translated.get(language, "").strip()
        if not value or (len(original) > 100 and len(value) < len(original) * ratio):
            return False
        if not numbers.issubset(numeric_tokens(value)):
            return False
    return True
