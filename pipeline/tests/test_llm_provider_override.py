from pipeline.common import llm


def test_gemini_provider_override(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "gemini")

    assert llm._route(llm.LOW) == ("gemini", llm.settings.gemini_model)
    assert llm.model_label(llm.LOW) == f"gemini:{llm.settings.gemini_model}"


def test_gemini_chat_dispatch(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "gemini")
    seen = {}

    def fake_chat(system, user, **kwargs):
        seen.update(system=system, user=user, **kwargs)
        return "ok"

    monkeypatch.setattr(llm.gemini, "chat", fake_chat)

    assert llm.chat(llm.LOW, "system", "user", max_tokens=321, temperature=0.4) == "ok"
    assert seen == {
        "system": "system",
        "user": "user",
        "model": llm.settings.gemini_model,
        "max_tokens": 321,
        "temperature": 0.4,
    }
