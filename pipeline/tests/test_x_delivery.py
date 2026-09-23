import json
import fcntl
import argparse
from pathlib import Path
from datetime import datetime, timezone
import pytest
from pipeline.jobs import x_delivery as job


def package(tmp_path):
    p = tmp_path / 'tweets_test.jsonl'
    p.write_text(json.dumps({'tweet_id':'1','created_at':datetime.now(timezone.utc).isoformat(),
                            'author_handle':'author','text':'$AAPL opinion','cashtags':['AAPL']})+'\n')
    return p


def test_dedup_queue_and_verified_job_never_republished(tmp_path):
    inbox = tmp_path/'inbox'
    p = package(tmp_path)
    a = job.enqueue(p,inbox)
    b = job.enqueue(p,inbox)
    assert a['packageHash']==b['packageHash']
    calls=[]
    def process(item, inbox):
        calls.append(item['packageHash'])
        return {'databaseVerified':True,'revision':'a'*64}
    assert job.run(inbox,processor=process)['status']=='verified'
    assert job.run(inbox,processor=process)['status']=='idle'
    assert len(calls)==1
    assert p.exists()


def test_transient_failure_retries_but_caps_attempts(tmp_path):
    inbox=tmp_path/'inbox'; job.enqueue(package(tmp_path),inbox)
    def fail(*args): raise RuntimeError('secret must not enter receipt')
    for expected in ['retry','retry','needs_attention']:
        result=job.run(inbox,processor=fail)
        assert result['status']==expected
        assert result['error']=='RuntimeError'
    assert job.run(inbox,processor=fail)['status']=='needs_attention'


def test_successful_retry_clears_previous_failure_reason(tmp_path):
    inbox = tmp_path / 'inbox'
    job.enqueue(package(tmp_path), inbox)

    def fail(*_args):
        raise RuntimeError('worker_failed')

    assert job.run(inbox, processor=fail)['status'] == 'retry'
    result = job.run(inbox, processor=lambda *_: {'databaseVerified': True, 'revision': 'a' * 64})
    assert result['status'] == 'verified'
    assert 'error' not in result
    assert 'reason' not in result


def test_crashed_running_job_resumes_and_lock_prevents_overlap(tmp_path):
    inbox=tmp_path/'inbox'; item=job.enqueue(package(tmp_path),inbox)
    path=inbox/(item['packageHash']+'.json')
    item.update(status='running',attempts=1);path.write_text(json.dumps(item))
    with (inbox/'.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        assert job.run(inbox)['status']=='busy'
    assert job.run(inbox,processor=lambda *_:{'databaseVerified':True,'revision':'b'*64})['attempts']==2


def test_changed_package_and_old_package_never_launch_processing(tmp_path,monkeypatch):
    inbox=tmp_path/'inbox'; p=package(tmp_path);item=job.enqueue(p,inbox)
    p.write_text(p.read_text().replace('opinion','changed'))
    def forbidden(*args,**kwargs):pytest.fail('No process should launch')
    monkeypatch.setattr(job,'command',forbidden)
    assert job.run(inbox)['status']=='needs_attention'
    p.write_text(json.dumps({'tweet_id':'2','created_at':'2020-01-01T00:00:00Z',
                            'author_handle':'a','text':'old','cashtags':[]})+'\n')
    job.enqueue(p,inbox)
    assert job.run(inbox)['status']=='needs_attention'


def test_incomplete_verification_cannot_mark_published(tmp_path):
    inbox=tmp_path/'inbox';job.enqueue(package(tmp_path),inbox)
    result=job.run(inbox,processor=lambda *_:{'databaseVerified':False,'revision':'b'*64})
    assert result['status']=='retry'
    assert 'revision' not in result


def test_x_delivery_cli_reports_failed_queue_attempt(tmp_path, monkeypatch):
    from pipeline.cli.commands import x_delivery

    parser = argparse.ArgumentParser()
    x_delivery.register_commands(parser.add_subparsers(dest='command'), tmp_path)
    monkeypatch.setattr(x_delivery, 'run', lambda _inbox: {'status': 'retry'})
    args = parser.parse_args(['x-delivery'])
    with pytest.raises(SystemExit) as stopped:
        args.func(args)
    assert stopped.value.code == 1


def test_operator_retry_keeps_cumulative_attempts_and_reason(tmp_path):
    inbox = tmp_path / 'inbox'
    item = job.enqueue(package(tmp_path), inbox)

    def fail(*_args):
        raise RuntimeError('worker_failed')

    for _ in range(3):
        job.run(inbox, processor=fail)
    with pytest.raises(ValueError, match='reason'):
        job.retry(inbox, item['packageHash'], '')
    restarted = job.retry(inbox, item['packageHash'], 'Backfill merge fixed')
    assert restarted['status'] == 'queued'
    assert restarted['attempts'] == 0 and restarted['totalAttempts'] == 3
    assert restarted['lastRetryReason'] == 'Backfill merge fixed'
    verified = job.run(inbox, processor=lambda *_: {'databaseVerified': True, 'revision': 'a' * 64})
    assert verified['status'] == 'verified' and verified['totalAttempts'] == 4


def test_publication_uses_system_proxy_when_shell_has_none(monkeypatch):
    monkeypatch.delenv('HTTPS_PROXY', raising=False)
    monkeypatch.setattr(job, 'getproxies', lambda: {'https': 'http://127.0.0.1:7897'})
    environment = job._publication_environment()
    assert environment['HTTPS_PROXY'] == 'http://127.0.0.1:7897'
    assert environment['X_INGEST_ENABLED'] == 'false'
