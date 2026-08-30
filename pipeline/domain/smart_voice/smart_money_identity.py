"""Stable consumer-facing aliases for pseudonymous Smart Money accounts."""
from __future__ import annotations

import hashlib
from collections.abc import Iterable


_FIRST_NAMES = (
    "Aiden", "Amara", "Anya", "Aria", "Atlas", "Audrey", "Beau", "Billie",
    "Briar", "Caleb", "Cameron", "Celeste", "Chloe", "Cole", "Dakota", "Eden",
    "Ellis", "Esme", "Eva", "Felix", "Freya", "Gideon", "Hazel", "Hudson",
    "Indigo", "Iris", "Jade", "Jasper", "Juno", "Kieran", "Leila", "Leo",
    "Luna", "Maeve", "Mateo", "Maya", "Micah", "Milo", "Naomi", "Nico",
    "Nova", "Olive", "Orion", "Otis", "Phoebe", "Remy", "River", "Rory",
    "Sage", "Sasha", "Sienna", "Silas", "Skye", "Stella", "Talia", "Theo",
    "Tessa", "Tristan", "Vera", "Wren", "Xander", "Yara", "Zane", "Zoe",
    "Aaron", "Ada", "Adrian", "Aisha", "Alina", "Andre", "Aspen", "Ayla",
    "Bella", "Ben", "Bodhi", "Brynn", "Caden", "Celine", "Clara", "Cody",
    "Cyrus", "Daisy", "Daria", "Declan", "Delilah", "Devin", "Eliana", "Elio",
    "Elsie", "Ethan", "Ezra", "Faye", "Finn", "Flora", "Gemma", "George",
    "Gia", "Hana", "Hugo", "Isla", "Ivan", "Ivy", "Jesse", "Jonah",
    "Josie", "Julian", "Kaia", "Kenji", "Lana", "Lara", "Layla", "Luca",
    "Mabel", "Mara", "Mira", "Nia", "Nolan", "Opal", "Owen", "Piper",
    "Rhea", "Ronan", "Rose", "Rowan", "Sora", "Tyler", "Vivian", "Wyatt",
)

_AVATAR_VARIANT_COUNT = 54
_AVATAR_STEPS = (1, 5, 7, 11, 13, 17, 19, 23, 25, 29, 31, 35, 37, 41, 43, 47, 49, 53)


def smart_money_public_identity(identity_key: str) -> dict[str, str | int]:
    """Return a deterministic alias without implying a verified real identity."""
    normalized = identity_key.strip().lower()
    digest = hashlib.sha256(normalized.encode("utf-8")).digest()
    first_name = _FIRST_NAMES[digest[0] % len(_FIRST_NAMES)]
    return {
        "displayName": first_name,
        "avatarVariant": digest[2] % _AVATAR_VARIANT_COUNT + 1,
    }


def smart_money_public_identities(identity_keys: Iterable[str]) -> dict[str, dict[str, str | int]]:
    """Allocate stable single-name aliases without duplicates inside one account pool."""
    normalized_keys = {identity_key.strip().lower() for identity_key in identity_keys}
    if len(normalized_keys) > len(_FIRST_NAMES):
        raise ValueError(f"Smart Money alias pool supports at most {len(_FIRST_NAMES)} accounts")
    if len(normalized_keys) > _AVATAR_VARIANT_COUNT:
        raise ValueError(f"Smart Money avatar pool supports at most {_AVATAR_VARIANT_COUNT} accounts")

    assigned_names: set[str] = set()
    assigned_avatars: set[int] = set()
    identities: dict[str, dict[str, str | int]] = {}
    ordered_keys = sorted(
        normalized_keys,
        key=lambda value: hashlib.sha256(value.encode("utf-8")).digest(),
    )
    for normalized in ordered_keys:
        digest = hashlib.sha256(normalized.encode("utf-8")).digest()
        start = int.from_bytes(digest[:2], "big") % len(_FIRST_NAMES)
        step = (int.from_bytes(digest[3:5], "big") % len(_FIRST_NAMES)) | 1
        for offset in range(len(_FIRST_NAMES)):
            name = _FIRST_NAMES[(start + offset * step) % len(_FIRST_NAMES)]
            if name in assigned_names:
                continue
            assigned_names.add(name)
            avatar_start = int.from_bytes(digest[5:7], "big") % _AVATAR_VARIANT_COUNT
            avatar_step = _AVATAR_STEPS[digest[7] % len(_AVATAR_STEPS)]
            for avatar_offset in range(_AVATAR_VARIANT_COUNT):
                avatar_variant = (avatar_start + avatar_offset * avatar_step) % _AVATAR_VARIANT_COUNT + 1
                if avatar_variant not in assigned_avatars:
                    assigned_avatars.add(avatar_variant)
                    break
            else:  # pragma: no cover - guarded by the capacity check above
                raise RuntimeError("Smart Money avatar pool is exhausted")
            identities[normalized] = {"displayName": name, "avatarVariant": avatar_variant}
            break
        else:  # pragma: no cover - guarded by the capacity check above
            raise RuntimeError("Smart Money alias pool is exhausted")
    return identities
