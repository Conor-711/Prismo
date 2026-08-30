from pipeline.domain.smart_voice.smart_money_identity import (
    smart_money_public_identities,
    smart_money_public_identity,
)


def test_smart_money_public_identity_is_stable_and_human_readable() -> None:
    address = "0x89c0fee4b7ca37711219092cd1c0d2b4f7af87c1"

    first = smart_money_public_identity(address)
    second = smart_money_public_identity(address.upper())

    assert first == second
    assert len(first["displayName"].split()) == 1
    assert not first["displayName"].endswith(".")
    assert not first["displayName"].startswith("0x")
    assert 1 <= first["avatarVariant"] <= 54


def test_smart_money_public_identity_changes_for_another_account() -> None:
    first = smart_money_public_identity("0x1111111111111111111111111111111111111111")
    second = smart_money_public_identity("0x2222222222222222222222222222222222222222")

    assert first != second


def test_account_pool_allocates_unique_single_names() -> None:
    addresses = [f"0x{index:040x}" for index in range(54)]

    identities = smart_money_public_identities(addresses)
    names = [identity["displayName"] for identity in identities.values()]
    avatars = [identity["avatarVariant"] for identity in identities.values()]

    assert len(names) == len(set(names))
    assert all(len(name.split()) == 1 for name in names)
    assert len(avatars) == len(set(avatars))
