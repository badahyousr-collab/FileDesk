import os
import sys
import threading
import time
import logging
import faulthandler
import re
from datetime import datetime, timezone
from collections import Counter
from logging.handlers import RotatingFileHandler
from pathlib import Path

from PySide6.QtCore import QObject, Property, Signal, Slot, QStandardPaths, QTimer, QUrl, QThread, qInstallMessageHandler, QLockFile
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QApplication, QFileDialog, QMessageBox
from PySide6.QtQml import QQmlApplicationEngine

from filedesk.settings import Settings
from filedesk.operations import Journal, Cancelled, discover, plan, execute, undo, render_name, friendly_error


class Task(QThread):
    result = Signal(object)
    failed = Signal(str)
    progress = Signal(int, int)

    def __init__(self, action, parent):
        super().__init__(parent)
        self.action = action
        self.cancel = threading.Event()
        self.last_progress = 0

    def report(self, done, total):
        now = time.monotonic()
        if done == total or now - self.last_progress > .05:
            self.last_progress = now
            self.progress.emit(done, total)

    def run(self):
        try:
            self.result.emit(self.action(self.cancel, self.report))
        except Cancelled:
            self.failed.emit("Операция остановлена")
        except Exception as exc:
            logging.getLogger("filedesk").exception("Background operation failed")
            self.failed.emit(friendly_error(exc))


class Backend(QObject):
    changed = Signal()
    rowsChanged = Signal()
    historyChanged = Signal()

    def __init__(self, settings, journal_path=None):
        super().__init__()
        self.settings = settings
        self.journal_path = Path(journal_path) if journal_path else settings.path.with_suffix(".history.sqlite3")
        self._dark = settings.get("theme", "dark") != "light"
        self._collapsed = settings.get("collapsed", "false") == "true"
        self._progress = 0
        self._running = False
        self._status = "Добавьте файлы или папку"
        self._rows = []
        self._display_rows = []
        self._history = []
        self._can_undo = False
        self._ready = False
        self._task = None
        self._demo = False
        self._demo_rows = []
        self._demo_history = []
        self._demo_before = []
        self._demo_last_records = []
        self._notice = ""
        self.options = dict(template="{name}_{n:03d}", start=1, find="", replace="")
        self.preview_timer = QTimer(self)
        self.preview_timer.setSingleShot(True)
        self.preview_timer.setInterval(350)
        self.preview_timer.timeout.connect(self.preview)
        journal = Journal(self.journal_path)
        journal.recover()
        journal.close()
        self.refresh_history()
        # Kept only for the clearly labelled UI demonstration.
        self.timer = QTimer(self)
        self.timer.setInterval(160)
        self.timer.timeout.connect(self.tick)

    @Property(bool, notify=changed)
    def dark(self): return self._dark

    @Property(bool, notify=changed)
    def collapsed(self): return self._collapsed

    @Property(float, notify=changed)
    def progress(self): return self._progress / 100

    @Property(bool, notify=changed)
    def running(self): return self._running

    @Property(str, notify=changed)
    def status(self): return self._status

    @Property('QVariantList', notify=rowsChanged)
    def rows(self): return self._demo_rows if self._demo else self._display_rows

    @Property('QVariantList', notify=historyChanged)
    def history(self): return self._demo_history if self._demo else self._history

    @Property(bool, notify=changed)
    def canRun(self):
        return (self._demo or self._ready) and not self._running and bool(self.rows) and not any(r['error'] for r in self.rows) and any(r['status'] == 'Готов к запуску' for r in self.rows)

    @Property(bool, notify=changed)
    def canUndo(self): return (bool(self._demo_before) if self._demo else self._can_undo) and not self._running

    @Property(bool, notify=changed)
    def demo(self): return self._demo

    @Property(str, notify=changed)
    def notice(self): return self._notice

    @Property(int, notify=changed)
    def readyCount(self): return sum(r['status'] == 'Готов к запуску' for r in self.rows)

    @Property(str, notify=changed)
    def actionHint(self):
        if self._running:
            return self._status
        if not self.rows:
            return "Выберите файлы или перетащите их в окно"
        if any(r['error'] for r in self.rows):
            return "Исправьте отмеченные строки или уберите их из списка"
        if self.canRun:
            return f"Будет переименовано: {self.readyCount}. Содержимое файлов не изменится."
        if any(r['status'] in ('Готово', 'Отменено') for r in self.rows):
            return self._status
        return "Новые имена совпадают с исходными. Измените настройки справа."

    @Slot()
    def dismissNotice(self):
        self._notice = ""
        self.changed.emit()

    @Slot()
    def chooseFiles(self):
        if self._running:
            return
        try:
            selected, _ = QFileDialog.getOpenFileNames(None, "Добавить файлы в FileDesk", self.settings.get("last_directory", ""), "Все файлы (*)")
            if selected:
                self.settings.set("last_directory", str(Path(selected[0]).parent))
                self.addPaths(selected)
        except Exception as exc:
            self.task_error(friendly_error(exc))

    @Slot()
    def chooseFolder(self):
        if self._running:
            return
        try:
            selected = QFileDialog.getExistingDirectory(None, "Добавить папку в FileDesk", self.settings.get("last_directory", ""))
            if selected:
                self.settings.set("last_directory", selected)
                self.addPaths([selected])
        except Exception as exc:
            self.task_error(friendly_error(exc))

    @Slot()
    def openLogs(self):
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.settings.path.parent)))

    @Slot()
    def toggleTheme(self):
        self._dark = not self._dark
        self.settings.set("theme", "dark" if self._dark else "light")
        self.changed.emit()

    @Slot()
    def toggleSidebar(self):
        self._collapsed = not self._collapsed
        self.settings.set("collapsed", str(self._collapsed).lower())
        self.changed.emit()

    def refresh_history(self):
        journal = Journal(self.journal_path)
        try:
            self._history = journal.history()
            self._can_undo = journal.undoable() is not None
        finally:
            journal.close()
        self.historyChanged.emit()
        self.changed.emit()

    def launch(self, action, handler, message):
        if self._running:
            return
        self._running = True
        self._progress = 0
        self._status = message
        self._notice = ""
        self.preview_timer.stop()
        task = Task(action, self)
        self._task = task
        # QObject slots ensure all model changes run on the GUI thread.
        self._handler = handler
        task.result.connect(self.task_result)
        task.failed.connect(self.task_error)
        task.progress.connect(self.task_progress)
        task.finished.connect(self.task_finished)
        self.changed.emit()
        task.start()

    @Slot(object)
    def task_result(self, value):
        try:
            self._handler(value)
        except Exception as exc:
            logging.getLogger("filedesk").exception("Result delivery failed")
            self.task_error(friendly_error(exc))

    @Slot(str)
    def task_error(self, message):
        self._ready = False
        self._status = message
        self._notice = message
        self.changed.emit()

    @Slot(int, int)
    def task_progress(self, done, total):
        self._progress = 100 * done / max(total, 1)
        self.changed.emit()

    @Slot()
    def task_finished(self):
        task = self._task
        self._task = None
        self._running = False
        if task:
            task.deleteLater()
        self.refresh_history()
        self.changed.emit()

    @Slot('QVariantList')
    def addUrls(self, urls):
        # Compatibility for callers using Qt URL objects.
        if hasattr(urls, 'toVariant'):
            urls = urls.toVariant()
        self.addPaths([u.toString() if isinstance(u, QUrl) else str(u) for u in urls])

    @Slot('QStringList')
    def addPaths(self, values):
        if self._running:
            self._notice = "Дождитесь окончания текущей операции или остановите её."
            self.changed.emit()
            return
        paths = []
        invalid = []
        for value in values:
            if not value:
                continue
            # Native dialogs return paths; drag-and-drop returns file: URLs.
            if value.lower().startswith("file:"):
                url = QUrl(value)
                if url.isLocalFile():
                    paths.append(url.toLocalFile())
                else:
                    invalid.append(value)
            elif re.match(r'^[a-zA-Z]:[\\/]', value) or value.startswith(("/", "\\")):
                paths.append(value)
            else:
                invalid.append(value)
        if not paths:
            self.task_error("Не удалось получить пути к файлам. Используйте кнопку «Добавить файлы»." if invalid else "Файлы не выбраны.")
            return
        if self._demo:
            self.setDemo(False)
        existing = [r['source'] for r in self._rows]
        options = dict(self.options)
        def action(cancel, report):
            found, problems = discover(existing + paths, cancel)
            return plan(found, options, cancel), problems + ["Неподдерживаемый путь: " + p for p in invalid]
        def accept(value):
            rows, problems = value
            self.set_rows(rows)
            self._ready = True
            self._status = f"В очереди файлов: {len(rows)}"
            if problems:
                self._notice = "\n".join(problems[:20])
            elif not rows:
                self._notice = "В выбранной папке нет доступных файлов. Выберите другую папку или отдельные файлы."
            self.changed.emit()
        self.launch(action, accept, "Добавляю файлы…")

    def set_rows(self, rows):
        self._rows = rows
        # Windows file IDs can exceed Qt's signed 64-bit QVariant limit.
        # Keep fingerprints in Python only; QML needs presentation fields.
        self._display_rows = [{key: value for key, value in row.items() if key != 'stamp'} for row in rows]
        self.rowsChanged.emit()
        self.changed.emit()

    @Slot(str, int, str, str)
    def configure(self, template, start, find, replace):
        if self._running:
            return
        self.options = dict(template=template, start=start, find=find, replace=replace)
        self._ready = False
        if self._demo:
            self.preview_demo()
        else:
            self.changed.emit()
            self.preview_timer.start()

    @Slot()
    def preview(self):
        if self._demo:
            self.preview_demo()
            return
        if self._running or not self._rows:
            return
        paths = [r['source'] for r in self._rows]
        options = dict(self.options)
        def accept(rows):
            self.set_rows(rows)
            self._ready = True
            errors = sum(bool(r['error']) for r in rows)
            self._status = f"Предпросмотр: {len(rows)} файлов, ошибок: {errors}"
        self.launch(lambda cancel, report: plan(paths, options, cancel), accept, "Проверяю имена и совпадения…")

    @Slot()
    def rename(self):
        if self._demo:
            self.startDemo()
            return
        if not self.canRun:
            return
        rows = [dict(r) for r in self._rows]
        def action(cancel, report):
            journal = Journal(self.journal_path)
            try:
                return execute(rows, journal, cancel, report)
            finally:
                journal.close()
        def accept(result):
            self.set_rows(result)
            self._ready = False
            done = sum(r['status'] == 'Готово' for r in result)
            errors = sum(bool(r['error']) for r in result)
            skipped = sum(r['status'] == 'Пропущен' for r in result)
            self._status = f"Переименовано: {done} · Ошибок: {errors} · Пропущено: {skipped}"
        self.launch(action, accept, "Переименовываю файлы…")

    @Slot()
    def undoLast(self):
        if self._demo:
            if self.canUndo:
                self._demo_rows = [dict(r, status="Отменено") for r in self._demo_before]
                self._demo_before = []
                for record in self._demo_last_records:
                    if record['state'] == 'done':
                        record['state'] = 'undone'
                self._status = "Демо: исходные имена восстановлены"
                self.rowsChanged.emit()
                self.historyChanged.emit()
                self.changed.emit()
            return
        if not self.canUndo:
            return
        def action(cancel, report):
            journal = Journal(self.journal_path)
            try:
                return undo(journal, cancel, report)
            finally:
                journal.close()
        def accept(restored):
            mapping = dict(restored)
            for row in self._rows:
                if row['source'] in mapping:
                    row['source'] = mapping[row['source']]
                    row['name'] = Path(row['source']).name
                    row['newName'] = row['name']
                    row['target'] = row['source']
                    row['status'] = 'Отменено'
                    row['error'] = ''
            self._ready = False
            self.set_rows(self._rows)
            self._status = f"Восстановлено имён: {len(restored)}. Подробности и конфликты — в истории."
        self.launch(action, accept, "Проверяю файлы перед отменой…")

    @Slot()
    def clear(self):
        if self._demo and not self._running:
            self._demo_rows = []
            self.rowsChanged.emit()
            self.changed.emit()
            return
        if not self._running:
            self.preview_timer.stop()
            self.set_rows([])
            self._ready = False
            self._status = "Очередь очищена. Файлы на диске сохранены."
            self.changed.emit()

    @Slot(int)
    def remove(self, index):
        if self._demo and not self._running:
            if 0 <= index < len(self._demo_rows):
                self._demo_rows.pop(index)
                self.preview_demo()
            return
        if not self._running and 0 <= index < len(self._rows):
            self._rows.pop(index)
            self.set_rows(self._rows)
            self._ready = False
            self.changed.emit()
            self.preview()

    @Slot()
    def stop(self):
        if self._task:
            self._task.cancel.set()
            self._status = "Останавливаю после текущего файла…"
            self.changed.emit()
        else:
            self.stopDemo()

    @Slot()
    def shutdown(self):
        self.preview_timer.stop()
        if self._task:
            self._task.cancel.set()
            self._task.wait()

    @Slot(bool)
    def setDemo(self, enabled):
        if self._running or enabled == self._demo:
            return
        self.preview_timer.stop()
        self._demo = enabled
        self._notice = ""
        self._progress = 0
        if enabled:
            self._demo_rows = [dict(name=name, source="Демо / " + name, size=size, newName=name, target="", status="", error="") for name, size in [("Фото_лето.jpg", 2400000), ("Обложка.png", 840000), ("Заметки.txt", 12000)]]
            self._demo_before = []
            self.preview_demo()
            self._status = "Демо: примеры не связаны с файлами на компьютере"
        else:
            self._status = "Выберите файлы или папку"
            if self._rows:
                self.preview()
        self.rowsChanged.emit()
        self.historyChanged.emit()
        self.changed.emit()

    def preview_demo(self):
        for index, row in enumerate(self._demo_rows):
            try:
                if not 1 <= int(self.options['start']) <= 999999:
                    raise ValueError("Первый номер должен быть от 1 до 999999")
                name = render_name(Path(row['name']), self.options['start'] + index, self.options, time.time())
                row.update(newName=name, target="Демо / " + name, error="", status="Без изменений" if name == row['name'] else "Готов к запуску")
            except (ValueError, KeyError) as exc:
                row.update(newName="", status="Ошибка", error=str(exc))
        counts = Counter(r['newName'].casefold() for r in self._demo_rows if r['newName'])
        for row in self._demo_rows:
            if counts[row['newName'].casefold()] > 1:
                row.update(status="Ошибка", error="Несколько файлов получат одно имя")
        self.rowsChanged.emit()
        self.changed.emit()

    @Slot()
    def startDemo(self):
        if not self._demo or not self.canRun:
            return
        self._demo_last_records = []
        self._demo_before = [dict(r) for r in self._demo_rows]
        self._progress = 0
        self._running = True
        self._status = "Демо: переименование примеров…"
        self.timer.start()
        self.changed.emit()

    def tick(self):
        self._progress = min(100, self._progress + 10)
        if self._progress == 100:
            self.timer.stop()
            self._running = False
            for row in self._demo_rows:
                if row['status'] == 'Готов к запуску':
                    record = dict(source=row['source'], target=row['target'], state="done", error="", created=datetime.now(timezone.utc).isoformat(), demo=True)
                    self._demo_history.insert(0, record)
                    self._demo_last_records.append(record)
                    row.update(source=row['target'], name=row['newName'], status="Готово")
            self._demo_history = self._demo_history[:1000]
            self._status = "Демо завершено. Результат сохранён в демонстрационной истории."
            self.rowsChanged.emit()
            self.historyChanged.emit()
        self.changed.emit()

    @Slot()
    def stopDemo(self):
        if self._task:
            return
        self.timer.stop()
        self._running = False
        self._status = "Демонстрация остановлена"
        self.changed.emit()


def main():
    # Avoid GPU-driver-dependent Qt Quick crashes; users can explicitly override.
    os.environ.setdefault("QT_QUICK_BACKEND", "software")
    app = QApplication(sys.argv)
    app.setOrganizationName("pipisso")
    app.setApplicationName("FileDesk")
    app.setApplicationVersion("0.3.1")
    base = Path(os.environ.get("FILEDESK_DATA_DIR") or QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation))
    base.mkdir(parents=True, exist_ok=True)
    instance_lock = QLockFile(str(base / "instance.lock"))
    instance_lock.setStaleLockTime(0)
    if not instance_lock.tryLock(0):
        QMessageBox.information(None, "FileDesk", "FileDesk уже открыт. Вернитесь в существующее окно.")
        return 1
    handler = RotatingFileHandler(base / "filedesk.log", maxBytes=1024 * 1024, backupCount=2, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logging.getLogger("filedesk").addHandler(handler)
    crash_log = (base / "crash.log").open("a", encoding="utf-8")
    faulthandler.enable(file=crash_log)
    qInstallMessageHandler(lambda kind, context, message: logging.getLogger("filedesk").warning("Qt: %s", message))
    settings = Settings(base / "preferences.sqlite3")
    old_path = base / "filedesk.sqlite3"
    if old_path.exists() and settings.get("migrated", "") != "yes":
        old = Settings(old_path)
        try:
            for key, default in (("theme", "dark"), ("collapsed", "false"), ("last_directory", "")):
                settings.set(key, old.get(key, default))
            settings.set("migrated", "yes")
        finally:
            old.close()
    backend = Backend(settings, old_path)
    app.aboutToQuit.connect(backend.shutdown)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).parent / "qml" / "Main.qml")))
    if not engine.rootObjects():
        settings.close()
        return 1
    if "--self-test" in sys.argv:
        from filedesk.selftest import start_self_test
        start_self_test(app, backend, engine.rootObjects()[0], base)
    elif "--smoke" in sys.argv:
        QTimer.singleShot(800, app.quit)
    result = app.exec()
    del engine
    settings.close()
    qInstallMessageHandler(None)
    faulthandler.disable()
    crash_log.close()
    return result


if __name__ == "__main__":
    sys.exit(main())
