from pipeline.common import deepseek


def test_batch_can_disable_thinking_without_changing_default(monkeypatch):
    calls = []

    class Response:
        status_code = 200

        def json(self):
            return {"choices": [{"message": {"content": '{"ok":true}'}}]}

    def post(url, **kwargs):
        calls.append(kwargs["json"])
        return Response()

    monkeypatch.setattr(deepseek.requests, "post", post)
    monkeypatch.delenv("DEEPSEEK_THINKING", raising=False)
    deepseek.chat("JSON", "test", retries=1)
    assert "thinking" not in calls[-1]
    monkeypatch.setenv("DEEPSEEK_THINKING", "disabled")
    assert deepseek.messages_json("JSON", "test") == {"ok": True}
    assert calls[-1]["thinking"] == {"type": "disabled"}
