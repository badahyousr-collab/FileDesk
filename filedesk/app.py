import os
import sys
import threading
import time
from pathlib import Path

from PySide6.QtCore import QObject, Property, Signal, Slot, QStandardPaths, QTimer, QUrl, QThread
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from filedesk.settings import Settings
from filedesk.operations import Journal, Cancelled, discover, plan, execute, undo


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
            self.failed.emit(str(exc))


class Backend(QObject):
    changed = Signal()
    rowsChanged = Signal()
    historyChanged = Signal()

    def __init__(self, settings):
        super().__init__()
        self.settings = settings
        self._dark = settings.get("theme", "dark") != "light"
        self._collapsed = settings.get("collapsed", "false") == "true"
        self._progress = 0
        self._running = False
        self._status = "Добавьте файлы или папку"
        self._rows = []
        self._history = []
        self._can_undo = False
        self._ready = False
        self._task = None
        self.options = dict(template="{name}", start=1, find="", replace="")
        self.preview_timer = QTimer(self)
        self.preview_timer.setSingleShot(True)
        self.preview_timer.setInterval(350)
        self.preview_timer.timeout.connect(self.preview)
        journal = Journal(self.settings.path)
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
    def rows(self): return self._rows

    @Property('QVariantList', notify=historyChanged)
    def history(self): return self._history

    @Property(bool, notify=changed)
    def canRun(self):
        return self._ready and not self._running and bool(self._rows) and not any(r['error'] for r in self._rows) and any(r['status'] == 'Готов к запуску' for r in self._rows)

    @Property(bool, notify=changed)
    def canUndo(self): return self._can_undo and not self._running

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
        journal = Journal(self.settings.path)
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
        self._handler(value)

    @Slot(str)
    def task_error(self, message):
        self._ready = False
        self._status = message
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
        if self._running:
            return
        paths = []
        for value in urls:
            url = value if isinstance(value, QUrl) else QUrl(str(value))
            if url.isLocalFile():
                paths.append(url.toLocalFile())
        if not paths:
            return
        existing = [r['source'] for r in self._rows]
        options = dict(self.options)
        def action(cancel, report):
            found, problems = discover(existing + paths, cancel)
            return plan(found, options, cancel), problems
        def accept(value):
            rows, problems = value
            self.set_rows(rows)
            self._ready = True
            self._status = f"Добавлено файлов: {len(rows)}" + (f". Предупреждений: {len(problems)}. {problems[0]}" if problems else "")
        self.launch(action, accept, "Читаю список файлов…")

    def set_rows(self, rows):
        self._rows = rows
        self.rowsChanged.emit()
        self.changed.emit()

    @Slot(str, int, str, str)
    def configure(self, template, start, find, replace):
        if self._running:
            return
        self.options = dict(template=template, start=start, find=find, replace=replace)
        self._ready = False
        self.changed.emit()
        self.preview_timer.start()

    @Slot()
    def preview(self):
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
        if not self.canRun:
            return
        rows = [dict(r) for r in self._rows]
        def action(cancel, report):
            journal = Journal(self.settings.path)
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
        if not self.canUndo:
            return
        def action(cancel, report):
            journal = Journal(self.settings.path)
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
            self.rowsChanged.emit()
            self._status = f"Восстановлено имён: {len(restored)}. Подробности и конфликты — в истории."
        self.launch(action, accept, "Проверяю файлы перед отменой…")

    @Slot()
    def clear(self):
        if not self._running:
            self.preview_timer.stop()
            self.set_rows([])
            self._ready = False
            self._status = "Очередь очищена. Файлы на диске сохранены."
            self.changed.emit()

    @Slot(int)
    def remove(self, index):
        if not self._running and 0 <= index < len(self._rows):
            self._rows.pop(index)
            self.rowsChanged.emit()
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

    @Slot()
    def startDemo(self):
        if self._running:
            return
        self._progress = 0
        self._running = True
        self._status = "Демонстрация: файлы на диске не изменяются"
        self.timer.start()
        self.changed.emit()

    def tick(self):
        self._progress = min(100, self._progress + 4)
        if self._progress == 100:
            self.timer.stop()
            self._running = False
            self._status = "Демонстрация завершена · 3 примера, 1 ошибка"
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
    app = QGuiApplication(sys.argv)
    app.setOrganizationName("pipisso")
    app.setApplicationName("FileDesk")
    app.setApplicationVersion("0.2.0")
    base = Path(os.environ.get("FILEDESK_DATA_DIR") or QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation))
    settings = Settings(base / "filedesk.sqlite3")
    backend = Backend(settings)
    app.aboutToQuit.connect(backend.shutdown)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).parent / "qml" / "Main.qml")))
    if not engine.rootObjects():
        settings.close()
        return 1
    if "--smoke" in sys.argv:
        QTimer.singleShot(800, app.quit)
    result = app.exec()
    del engine
    settings.close()
    return result


if __name__ == "__main__":
    sys.exit(main())
