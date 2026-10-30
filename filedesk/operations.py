"""File discovery, read-only plans and journalled, no-overwrite renames.

No Qt dependency. A batch is intentionally not atomic: completed files remain
journalled when another file fails or cancellation is requested.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import stat
import string
import threading
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable


def friendly_error(exc):
    if isinstance(exc, FileNotFoundError):
        return "Файл или папка больше не существует. Добавьте файлы заново."
    if isinstance(exc, PermissionError) or getattr(exc, "winerror", None) in (5, 32, 33):
        return "Нет доступа или файл открыт другой программой. Закройте его и проверьте права на папку."
    if isinstance(exc, FileExistsError):
        return "Такое имя уже занято. Измените имя или начальный номер."
    return str(exc)


class Cancelled(Exception):
    pass


def native(path: Path) -> Path:
    """Allow long absolute paths on Windows; retain readable paths in the UI."""
    if os.name != "nt":
        return path
    value = str(path.absolute())
    if value.startswith("\\\\?\\"):
        return Path(value)
    return Path("\\\\?\\UNC\\" + value[2:] if value.startswith("\\\\") else "\\\\?\\" + value)


def is_junction(path: Path) -> bool:
    return getattr(path, "is_junction", lambda: False)()


def path_key(path: Path) -> str:
    return str(path.absolute()).casefold()


def discover(paths, cancel: threading.Event):
    files, problems, seen = [], [], set()

    def add(path):
        if cancel.is_set():
            raise Cancelled()
        key = path_key(path)
        if key in seen:
            return
        seen.add(key)
        try:
            info = native(path).lstat()
            if stat.S_ISLNK(info.st_mode) or is_junction(native(path)):
                problems.append(f"Пропущена ссылка: {path}")
            elif stat.S_ISREG(info.st_mode):
                files.append(str(path.absolute()))
        except OSError as exc:
            problems.append(f"{path}: {friendly_error(exc)}")

    for item in paths:
        path = Path(item).absolute()
        if cancel.is_set():
            raise Cancelled()
        if native(path).is_symlink() or is_junction(native(path)):
            problems.append(f"Пропущена ссылка: {path}")
        elif native(path).is_dir():
            def onerror(exc):
                problems.append(str(exc))
            for root, dirs, names in os.walk(native(path), followlinks=False, onerror=onerror):
                if cancel.is_set():
                    raise Cancelled()
                dirs[:] = sorted(d for d in dirs if not (Path(root) / d).is_symlink() and not is_junction(Path(root) / d))
                for name in sorted(names):
                    # Keep display paths free of the Windows extended prefix.
                    relative = (Path(root) / name).relative_to(native(path))
                    add(path / relative)
        else:
            add(path)
    return files, problems


def validate_name(name: str):
    if not name or name in (".", ".."):
        raise ValueError("Пустое имя")
    if re.search(r'[<>:"/\\|?*\x00-\x1f]', name):
        raise ValueError("Недопустимый символ в имени")
    if name.endswith((" ", ".")):
        raise ValueError("Имя не может заканчиваться точкой или пробелом")
    stem = name.split(".")[0].rstrip(" ").upper()
    if re.fullmatch(r"CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³]|CONIN\$|CONOUT\$", stem):
        raise ValueError("Зарезервированное имя Windows")
    if len(name.encode("utf-16-le")) // 2 > 255:
        raise ValueError("Имя длиннее 255 символов UTF-16")


def render_name(path: Path, number: int, options: dict, modified: float) -> str:
    template = options.get("template", "{name}")
    if len(template) > 500:
        raise ValueError("Слишком длинный шаблон")
    for _, field, spec, conversion in string.Formatter().parse(template):
        if field is None:
            continue
        if field not in ("name", "n", "date") or conversion:
            raise ValueError("Доступны только {name}, {n:03d} и {date}")
        if spec and (field != "n" or not re.fullmatch(r"0?[1-9]?[0-9]?d", spec)):
            raise ValueError("Неверный формат номера")
    name = path.stem
    if options.get("find"):
        name = name.replace(options["find"], options.get("replace", ""))
    result = template.format(name=name, n=number, date=datetime.fromtimestamp(modified).strftime("%Y-%m-%d")) + path.suffix
    validate_name(result)
    return result


def plan(paths: list[str], options: dict, cancel: threading.Event):
    rows = []
    start = int(options.get("start", 1))
    if not 1 <= start <= 999999:
        raise ValueError("Первый номер должен быть от 1 до 999999")
    directories = {}
    for index, value in enumerate(paths):
        if cancel.is_set():
            raise Cancelled()
        src = Path(value)
        row = dict(source=str(src), target="", name=src.name, newName="", size=0, status="", error="")
        try:
            info = native(src).lstat()
            if not stat.S_ISREG(info.st_mode):
                raise ValueError("Разрешены только обычные файлы")
            new_name = render_name(src, start + index, options, info.st_mtime)
            dst = src.with_name(new_name)
            row.update(target=str(dst), newName=new_name, size=info.st_size,
                       stamp=[info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns])
            if str(dst) == str(src):
                row["status"] = "Без изменений"
            else:
                if src.parent not in directories:
                    with os.scandir(native(src.parent)) as entries:
                        directories[src.parent] = {entry.name.casefold() for entry in entries}
                if new_name.casefold() in directories[src.parent]:
                    raise ValueError("Имя уже занято (включая другой регистр)")
                row["status"] = "Готов к запуску"
        except (OSError, ValueError, KeyError) as exc:
            row.update(status="Ошибка", error=friendly_error(exc))
        rows.append(row)
    counts = Counter(path_key(Path(row["target"])) for row in rows if row["target"])
    for row in rows:
        if row["target"] and counts[path_key(Path(row["target"]))] > 1:
            row.update(status="Ошибка", error="Несколько файлов получат одно имя")
    return rows


def fingerprint(path: Path, cancel: threading.Event):
    before = native(path).lstat()
    if not stat.S_ISREG(before.st_mode):
        raise ValueError("Файл заменён ссылкой или недоступен")
    digest = hashlib.sha256()
    with native(path).open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            if cancel.is_set():
                raise Cancelled()
            digest.update(chunk)
    after = native(path).lstat()
    stamp = lambda s: [s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns]
    if stamp(before) != stamp(after):
        raise ValueError("Файл изменился во время проверки")
    return dict(stamp=stamp(after), sha256=digest.hexdigest())


def move_no_replace(src: Path, dst: Path):
    """Same-directory move without ever overwriting a destination file."""
    if src.parent != dst.parent:
        raise ValueError("Переименование допускается только в той же папке")
    with os.scandir(native(dst.parent)) as entries:
        if any(entry.name.casefold() == dst.name.casefold() for entry in entries):
            raise FileExistsError("Имя уже занято")
    if os.name == "nt":
        # Windows rename refuses existing destinations (unlike POSIX rename).
        os.rename(native(src), native(dst))
    else:
        os.link(src, dst, follow_symlinks=False)
        try:
            src.unlink()
        except OSError:
            dst.unlink()
            raise


class Journal:
    def __init__(self, path: Path):
        self.db = sqlite3.connect(path)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS batches (
            id INTEGER PRIMARY KEY, created TEXT NOT NULL, state TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS changes (
            id INTEGER PRIMARY KEY, batch INTEGER NOT NULL, source TEXT NOT NULL,
            target TEXT NOT NULL, fingerprint TEXT NOT NULL, state TEXT NOT NULL,
            error TEXT NOT NULL DEFAULT '');
        """)
        self.db.commit()

    def recover(self):
        # Never guess whether a pending rename happened before a crash.
        with self.db:
            self.db.execute("UPDATE batches SET state='interrupted' WHERE state='running'")
            self.db.execute("UPDATE changes SET state='uncertain', error='Операция прервана: проверьте оба пути вручную' WHERE state IN ('pending', 'undoing')")

    def begin(self):
        with self.db:
            return self.db.execute("INSERT INTO batches(created,state) VALUES (?, 'running')", (datetime.now(timezone.utc).isoformat(),)).lastrowid

    def add(self, batch, src, dst, identity):
        with self.db:
            return self.db.execute("INSERT INTO changes(batch,source,target,fingerprint,state) VALUES (?,?,?,?, 'pending')", (batch, str(src), str(dst), json.dumps(identity))).lastrowid

    def state(self, change, state, error=""):
        with self.db:
            self.db.execute("UPDATE changes SET state=?, error=? WHERE id=?", (state, error, change))

    def finish(self, batch, state):
        with self.db:
            self.db.execute("UPDATE batches SET state=? WHERE id=?", (state, batch))

    def history(self):
        self.db.row_factory = sqlite3.Row
        return [dict(row) for row in self.db.execute("SELECT c.*, b.created FROM changes c JOIN batches b ON b.id=c.batch ORDER BY c.id DESC LIMIT 1000")]

    def undoable(self):
        return self.db.execute("SELECT MAX(batch) FROM changes WHERE state='done'").fetchone()[0]

    def close(self):
        self.db.close()


def execute(rows: list[dict], journal: Journal, cancel: threading.Event, progress: Callable):
    if any(row["error"] for row in rows):
        raise ValueError("Сначала устраните ошибки предпросмотра")
    batch = journal.begin()
    output = []
    try:
        for index, original in enumerate(rows):
            row = dict(original)
            if cancel.is_set():
                row["status"] = "Пропущен"
                change = journal.add(batch, row["source"], row["target"], {})
                journal.state(change, "skipped")
            elif row["source"] == row["target"]:
                row["status"] = "Без изменений"
                change = journal.add(batch, row["source"], row["target"], {})
                journal.state(change, "unchanged")
            else:
                change = None
                moved = False
                try:
                    src, dst = Path(row["source"]), Path(row["target"])
                    identity = fingerprint(src, cancel)
                    if identity["stamp"] != row["stamp"]:
                        raise ValueError("Файл изменился после предпросмотра")
                    change = journal.add(batch, src, dst, identity)
                    if cancel.is_set():
                        raise Cancelled()
                    move_no_replace(src, dst)
                    moved = True
                    journal.state(change, "done")
                    row["status"] = "Готово"
                    row["source"] = str(dst)
                    row["name"] = dst.name
                except Cancelled:
                    row["status"] = "Пропущен"
                    if change is not None:
                        journal.state(change, "skipped")
                except (OSError, ValueError) as exc:
                    row.update(status="Ошибка", error=friendly_error(exc))
                    if change is None:
                        change = journal.add(batch, row["source"], row["target"], {})
                    journal.state(change, "uncertain" if moved else "failed", str(exc))
            output.append(row)
            progress(index + 1, len(rows))
        journal.finish(batch, "cancelled" if cancel.is_set() else ("errors" if any(r["error"] for r in output) else "done"))
    except BaseException:
        journal.finish(batch, "interrupted")
        raise
    return output


def undo(journal: Journal, cancel: threading.Event, progress: Callable):
    batch = journal.undoable()
    if batch is None:
        return []
    changes = journal.db.execute("SELECT id, source, target, fingerprint FROM changes WHERE batch=? AND state='done' ORDER BY id DESC", (batch,)).fetchall()
    restored = []
    for index, (change, source, target, saved) in enumerate(changes):
        if cancel.is_set():
            break
        moved = False
        try:
            if fingerprint(Path(target), cancel) != json.loads(saved):
                raise ValueError("Файл изменился: отмена запрещена")
            journal.state(change, "undoing")
            move_no_replace(Path(target), Path(source))
            moved = True
            journal.state(change, "undone")
            restored.append((target, source))
        except Cancelled:
            break
        except (OSError, ValueError) as exc:
            journal.state(change, "uncertain" if moved else "done", str(exc))
        progress(index + 1, len(changes))
    return restored
