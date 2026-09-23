"""Conservative publication checks, not a claim of semantic translation accuracy."""
from decimal import Decimal
import re


_MONEY_SOURCE = re.compile(r"\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?)\s*(billion|million|B|M|K)\b", re.I)
_SCALED_RANGE = re.compile(r"(\d+(?:\.\d+)?)\s*[-–]\s*\d+(?:\.\d+)?\s*(B|M|K)\b", re.I)
_MONEY_ZH = re.compile(r"(\d+(?:,\d{3})*(?:\.\d+)?)\s*(十亿|百万|亿|万)(?:美?元)?")
_SOURCE_SCALE = {"billion": Decimal("1000"), "b": Decimal("1000"),
                 "million": Decimal("1"), "m": Decimal("1"), "k": Decimal("0.001")}
_ZH_SCALE = {"十亿": Decimal("1000"), "亿": Decimal("100"),
             "百万": Decimal("1"), "万": Decimal("0.01")}
_SMALL_ZH = {"1": "一", "2": "二", "3": "三", "4": "四", "5": "五"}
_SMALL_EN_ORDINALS = {"1": "first", "2": "second", "3": "third",
                      "4": "fourth", "5": "fifth"}
_MONTHS_EN = {"1": "January", "2": "February", "3": "March", "4": "April",
              "5": "May", "6": "June", "7": "July", "8": "August",
              "9": "September", "10": "October", "11": "November", "12": "December"}
_MONTH_ALIASES = {"1": "Jan(?:uary)?", "2": "Feb(?:ruary)?", "3": "Mar(?:ch)?",
                  "4": "Apr(?:il)?", "5": "May", "6": "Jun(?:e)?", "7": "Jul(?:y)?",
                  "8": "Aug(?:ust)?", "9": "Sep(?:t(?:ember)?)?", "10": "Oct(?:ober)?",
                  "11": "Nov(?:ember)?", "12": "Dec(?:ember)?"}


def numeric_tokens(value: str) -> set[str]:
    value = re.sub(r"https?://\S+", "", value)
    tokens = re.findall(r"(?<![\d.])(?:\d+(?:,\d{3})*(?:\.\d+)?|\.\d+)", value)
    return {(f"0{token}" if token.startswith(".") else token).replace(",", "") for token in tokens}


def missing_numeric_tokens(original: str, translated: str) -> set[str]:
    missing = numeric_tokens(original) - numeric_tokens(translated)
    if not missing:
        return set()
    money = {Decimal(amount.replace(",", "")) * _ZH_SCALE[unit]
             for amount, unit in _MONEY_ZH.findall(translated)}
    for amount, unit in _MONEY_SOURCE.findall(original):
        token = amount.replace(",", "")
        if token in missing and Decimal(token) * _SOURCE_SCALE[unit.lower()] in money:
            missing.remove(token)
    for amount, unit in _SCALED_RANGE.findall(original):
        if amount in missing and Decimal(amount) * _SOURCE_SCALE[unit.lower()] in money:
            missing.remove(amount)
    for token in list(missing):
        month_day = re.fullmatch(r"(1[0-2]|0?[1-9])\.(3[01]|[12]\d|0?[1-9])", token)
        if month_day and token in original:
            month, day = month_day.groups()
            alias = _MONTH_ALIASES.get(str(int(month)))
            english_date = alias and re.search(rf"\b{alias}\s+0?{int(day)}\b", translated, re.I)
            chinese_date = re.search(rf"(?<!\d)0?{int(month)}月0?{int(day)}日?", translated)
            if english_date or chinese_date:
                missing.remove(token)
                continue
        numeral = _SMALL_ZH.get(token)
        if numeral and re.search(rf"\bphase\s+{token}\b", original, re.I):
            if re.search(rf"(?:第?{numeral}(?:期|阶段))", translated):
                missing.remove(token)
                continue
        if numeral and re.search(rf"\b{token}\s+quarters?\b", original, re.I):
            if re.search(rf"{numeral}个?季度", translated):
                missing.remove(token)
                continue
        if numeral and re.search(rf"\bq{token}\b", original, re.I):
            if re.search(rf"第?{numeral}季度", translated):
                missing.remove(token)
                continue
        if numeral and re.search(rf"\b{token}(?:st|nd|rd|th)\b", original, re.I):
            if (re.search(rf"第?{numeral}(?:笔|批|次|轮|期|阶段)", translated)
                or re.search(rf"\b{_SMALL_EN_ORDINALS[token]}\b", translated, re.I)):
                missing.remove(token)
                continue
        if re.search(rf"(?<!\d){token}月", original) and _MONTH_ALIASES.get(token):
            if re.search(rf"\b{_MONTH_ALIASES[token]}\b", translated, re.I):
                missing.remove(token)
                continue
        if len(token) == 2 and f"20{token}" in numeric_tokens(translated):
            if re.search(rf"(?:['’]{token}s?\b|\b{token}['’]s?\b)", original):
                missing.remove(token)
    return missing


def validate_translation(original: str, translated: dict[str, str]) -> bool:
    # Missing numbers and extreme compression usually mean a summary or truncation.
    for language, ratio in (("zh", 0.12), ("en", 0.4)):
        value = translated.get(language, "").strip()
        if not value or (len(original) > 100 and len(value) < len(original) * ratio):
            return False
        if missing_numeric_tokens(original, value):
            return False
    return True
