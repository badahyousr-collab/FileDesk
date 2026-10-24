import os
import threading
from pathlib import Path

import pytest

from filedesk.operations import Journal, discover, plan, execute, undo, validate_name


def event():
    return threading.Event()


def files(tmp_path, names):
    paths = []
    for index, name in enumerate(names):
        path = tmp_path / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(f"content-{index}".encode())
        paths.append(str(path))
    return paths


def prepare(paths, template="photo_{n:03d}", **kwargs):
    return plan(paths, dict(template=template, start=1, **kwargs), event())


@pytest.fixture
def journal(tmp_path):
    j = Journal(tmp_path / 'history.sqlite3')
    yield j
    j.close()


@pytest.mark.parametrize('name', ['CON.jpg', 'LPT1.txt', 'aux', 'COM¹.png', 'CONIN$.txt', 'bad?.txt', '../bad', 'foo.', 'foo ', '', 'a'*256, 'x\x00.png'])
def test_windows_invalid_names(name):
    with pytest.raises(ValueError):
        validate_name(name)


def test_cyrillic_search_numbering_and_undo_after_restart(tmp_path, journal):
    paths = files(tmp_path, ['фото лето.jpg', 'фото море.png', 'пустой.txt'])
    Path(paths[2]).write_bytes(b'')
    rows = prepare(paths, '{name}_{n:03d}', find='фото', replace='снимок')
    assert rows[0]['newName'] == 'снимок лето_001.jpg'
    assert all(not row['error'] for row in rows)
    results = execute(rows, journal, event(), lambda *_: None)
    assert all(row['status'] == 'Готово' for row in results)
    assert not any(Path(path).exists() for path in paths)
    restarted = Journal(tmp_path / 'history.sqlite3')
    restarted.recover()
    restored = undo(restarted, event(), lambda *_: None)
    restarted.close()
    assert len(restored) == 3
    assert all(Path(path).exists() for path in paths)
    assert Path(paths[2]).read_bytes() == b''


def test_preview_conflicts_case_and_duplicate_targets(tmp_path):
    paths = files(tmp_path, ['a.jpg', 'b.jpg', 'PHOTO_001.JPG'])
    rows = prepare(paths[:2])
    assert rows[0]['error']
    assert all(row['error'] for row in prepare(paths[:2], 'same'))
    assert prepare(paths[:1], 'A')[0]['error']  # case-only rename intentionally blocked


@pytest.mark.parametrize('template', ['{unknown}', '{name.__class__}', '{n:999999d}', '{n!r}', '{', 'CON', '../{name}'])
def test_invalid_templates(tmp_path, template):
    paths = files(tmp_path, ['source.txt'])
    assert prepare(paths, template)[0]['error']


def test_no_overwrite_if_destination_appears_after_preview(tmp_path, journal):
    paths = files(tmp_path, ['a.jpg', 'b.jpg'])
    rows = prepare(paths)
    target = Path(rows[0]['target'])
    target.write_bytes(b'important')
    result = execute(rows, journal, event(), lambda *_: None)
    assert result[0]['error']
    assert target.read_bytes() == b'important'
    assert Path(paths[0]).exists()
    assert result[1]['status'] == 'Готово'
    assert journal.history()[1]['state'] == 'failed'


def test_changed_source_and_missing_source_are_recorded(tmp_path, journal):
    paths = files(tmp_path, ['a.txt', 'b.txt'])
    rows = prepare(paths)
    Path(paths[0]).write_bytes(b'changed since preview')
    Path(paths[1]).unlink()
    result = execute(rows, journal, event(), lambda *_: None)
    assert all(r['error'] for r in result)
    assert len(journal.history()) == 2
    assert all(h['state'] == 'failed' for h in journal.history())


def test_cancel_between_files_keeps_completed_changes_undoable(tmp_path, journal):
    paths = files(tmp_path, ['a.txt', 'b.txt', 'c.txt'])
    stop = event()
    result = execute(prepare(paths), journal, stop, lambda *_: stop.set())
    assert [r['status'] for r in result] == ['Готово', 'Пропущен', 'Пропущен']
    assert len(journal.history()) == 3
    assert len(undo(journal, event(), lambda *_: None)) == 1
    assert all(Path(path).exists() for path in paths)


def test_undo_rejects_changed_content_even_if_size_and_mtime_match(tmp_path, journal):
    path = files(tmp_path, ['a.txt'])[0]
    rows = prepare([path])
    execute(rows, journal, event(), lambda *_: None)
    target = Path(rows[0]['target'])
    st = target.stat()
    target.write_bytes(b'x' * st.st_size)
    os.utime(target, ns=(st.st_atime_ns, st.st_mtime_ns))
    assert undo(journal, event(), lambda *_: None) == []
    assert target.exists() and not Path(path).exists()
    assert journal.history()[0]['error']


def test_undo_does_not_overwrite_and_can_retry(tmp_path, journal):
    path = files(tmp_path, ['a.txt'])[0]
    execute(prepare([path]), journal, event(), lambda *_: None)
    Path(path).write_bytes(b'new file')
    assert undo(journal, event(), lambda *_: None) == []
    assert Path(path).read_bytes() == b'new file'
    Path(path).unlink()
    assert len(undo(journal, event(), lambda *_: None)) == 1
    assert Path(path).read_bytes() == b'content-0'


def test_discovery_deduplicates_recursive_input_and_skips_links(tmp_path):
    paths = files(tmp_path, ['folder/a.txt', 'folder/nested/b.txt'])
    try:
        (tmp_path / 'link').symlink_to(tmp_path / 'folder', target_is_directory=True)
    except OSError:
        pass  # Creating symlinks can require Windows developer mode.
    found, errors = discover([str(tmp_path / 'folder'), paths[0]], event())
    assert sorted(found) == sorted(paths)
    assert not errors
    found, errors = discover([str(tmp_path / 'missing')], event())
    assert not found and errors


def test_long_path(tmp_path, journal):
    paths = files(tmp_path, ['a'*90 + '/' + 'b'*90 + '/' + 'c'*90 + '/файл.txt'])
    result = execute(prepare(paths), journal, event(), lambda *_: None)
    assert result[0]['status'] == 'Готово'
    assert len(undo(journal, event(), lambda *_: None)) == 1


def test_permission_error_does_not_stop_batch(tmp_path, journal, monkeypatch):
    from filedesk import operations
    original = operations.move_no_replace
    paths = files(tmp_path, ['a.txt', 'b.txt'])
    def denied(src, dst):
        if src.name == 'a.txt':
            raise PermissionError('File locked or access denied')
        original(src, dst)
    monkeypatch.setattr(operations, 'move_no_replace', denied)
    result = execute(prepare(paths), journal, event(), lambda *_: None)
    assert result[0]['error'] and result[1]['status'] == 'Готово'


def test_crash_recovery_marks_ambiguous_changes_without_guessing(tmp_path, journal):
    batch = journal.begin()
    journal.add(batch, 'before', 'after', {})
    journal.recover()
    assert journal.history()[0]['state'] == 'uncertain'
    assert journal.undoable() is None
    assert journal.db.execute('SELECT state FROM batches').fetchone()[0] == 'interrupted'
