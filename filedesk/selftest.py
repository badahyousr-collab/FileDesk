"""Exercise the packaged UI and real files, using an isolated temporary folder."""
import json
import tempfile
import time
from pathlib import Path

from PySide6.QtCore import QObject, QTimer, QMetaObject, Qt, Q_ARG, QUrl
from PySide6.QtWidgets import QFileDialog
from PySide6.QtQuick import QQuickWindow  # Register the Python wrapper for screenshots.


def start_self_test(app, backend, window, output):
    runner = SelfTest(app, backend, window, output)
    app._selftest = runner
    runner.timer.start(40)


class SelfTest(QObject):
    def __init__(self, app, backend, window, output):
        super().__init__(app)
        self.app, self.backend, self.window, self.output = app, backend, window, output
        self.temp = tempfile.TemporaryDirectory(prefix='FileDesk-test-')
        self.root = Path(self.temp.name)
        self.source = self.root / 'Фото №1.txt'
        self.source.write_text('Original content', encoding='utf-8')
        self.target = self.root / 'Фото №1_001.txt'
        self.extra = self.root / 'Ещё один файл.txt'
        self.extra.write_text('Second file', encoding='utf-8')
        self.stage = 0
        self.deadline = time.monotonic() + 50
        self.navigation_ticks = 0
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.step)

    def button(self, name):
        def find(item):
            if item.objectName() == name:
                return item
            for child in item.childItems():
                found = find(child)
                if found is not None:
                    return found
            return None
        obj = find(self.window.contentItem())
        assert obj is not None, name
        assert obj.property('enabled'), name + ' is disabled'
        assert QMetaObject.invokeMethod(obj, 'clicked', Qt.DirectConnection)

    def step(self):
        b = self.backend
        try:
            assert time.monotonic() < self.deadline, 'UI operation timed out'
            if b.running:
                # Navigate and write preferences while real file jobs are active.
                self.navigation_ticks += 1
                self.window.setProperty('page', self.navigation_ticks % 4)
                if self.navigation_ticks % 3 == 0:
                    b.toggleTheme()
                    b.toggleSidebar()
                return
            if self.stage == 0:
                # Exercise the actual QML button -> Python dialog handler -> native path.
                original = QFileDialog.getOpenFileNames
                QFileDialog.getOpenFileNames = lambda *args, **kw: ([str(self.source)], '')
                try:
                    self.button('addFilesButton')
                finally:
                    QFileDialog.getOpenFileNames = original
            elif self.stage == 1:
                assert len(b.rows) == 1 and b.canRun, b.status
                assert self.window.findChild(QObject, 'fileList').property('count') == 1
                self.button('renameButton')
            elif self.stage == 2:
                assert self.target.read_text(encoding='utf-8') == 'Original content'
                assert not self.source.exists()
                self.button('nav2')
                assert self.window.property('page') == 2
                assert len(b.history) == 1 and b.history[0]['state'] == 'done'
                self.button('undoButton')
            elif self.stage == 3:
                assert self.source.exists() and not self.target.exists()
                assert b.history[0]['state'] == 'undone'
                # Exercise QML URL serialization used by the drop area.
                assert QMetaObject.invokeMethod(self.window, 'importFiles', Qt.DirectConnection, Q_ARG('QVariant', [QUrl.fromLocalFile(str(self.extra)).toString()]))
            elif self.stage == 4:
                assert len(b.rows) == 2, b.status
                self.button('demoButton')
                self.window.setProperty('page', 0)
                assert len(b.rows) == 3 and b.demo
                self.button('renameButton')
            elif self.stage == 5:
                assert len(b.history) == 3 and all(r['state']=='done' for r in b.history)
                self.button('nav2')
                assert self.window.findChild(QObject,'historyList').property('count') == 3
                self.button('undoButton')
                assert all(r['state']=='undone' for r in b.history)
                self.button('demoButton')
                assert len(b.history) == 1 and not b.demo
                self.window.setProperty('page',0)
            elif self.stage == 6:
                b.clear()
                stress = self.root / 'queue'
                stress.mkdir()
                for i in range(400):
                    (stress / f'file_{i}.txt').write_bytes(b'content' * 200)
                b.addPaths([str(stress)])
            elif self.stage == 7:
                assert len(b.rows) == 400 and b.canRun
                self.window.setProperty('page', 0)
                self.button('renameButton')
            elif self.stage == 8:
                assert len(list((self.root/'queue').glob('*_???.txt'))) == 400
                assert all(r['status'] == 'Готово' for r in b.rows), b.status
                assert self.navigation_ticks > 0
                b.undoLast()
            elif self.stage == 9:
                assert all((self.root/'queue'/f'file_{i}.txt').exists() for i in range(400))
                self.window.setProperty('page', 0)
                self.window.grabWindow().save(str(self.output / 'self-test.png'))
                self.finish(True)
                return
            self.stage += 1
        except Exception as exc:
            self.finish(False, repr(exc))

    def finish(self, ok, error=''):
        self.timer.stop()
        self.backend.shutdown()
        (self.output/'self-test.json').write_text(json.dumps(dict(success=ok, stage=self.stage, error=error), ensure_ascii=False), encoding='utf-8')
        self.temp.cleanup()
        self.app.exit(0 if ok else 1)
