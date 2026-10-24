import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from pathlib import Path
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from filedesk.app import Backend
from filedesk.settings import Settings


def test_ui_loads_and_demo_can_stop(tmp_path):
    app = QGuiApplication.instance() or QGuiApplication([])
    store = Settings(tmp_path / "settings.sqlite3")
    backend = Backend(store)
    engine = QQmlApplicationEngine()
    warnings = []
    engine.warnings.connect(lambda messages: warnings.extend(m.toString() for m in messages))
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parents[1] / "filedesk/qml/Main.qml")))
    assert engine.rootObjects()
    window = engine.rootObjects()[0]
    for dark in (False, True):
        if backend.dark != dark:
            backend.toggleTheme()
        for page in range(4):
            window.setProperty("page", page)
            app.processEvents()
    window.setProperty("page", 0)
    window.setProperty("demo", True)
    app.processEvents()
    backend.startDemo()
    backend.tick()
    assert backend.running and backend.progress > 0
    backend.stopDemo()
    assert not backend.running
    backend.startDemo()
    for _ in range(25):
        backend.tick()
    assert backend.progress == 1 and not backend.running
    backend.toggleSidebar()
    app.processEvents()
    assert not warnings, warnings
    window.close()
    del window
    del engine
    store.close()


def test_real_files_through_backend_and_qml(tmp_path):
    import time
    app = QGuiApplication.instance() or QGuiApplication([])
    store = Settings(tmp_path / 'settings.sqlite3')
    backend = Backend(store)
    engine = QQmlApplicationEngine()
    warnings = []
    engine.warnings.connect(lambda messages: warnings.extend(m.toString() for m in messages))
    engine.rootContext().setContextProperty('backend', backend)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parents[1] / 'filedesk/qml/Main.qml')))
    window = engine.rootObjects()[0]
    def wait():
        deadline = time.monotonic() + 5
        while backend.running and time.monotonic() < deadline:
            app.processEvents()
            time.sleep(.005)
        app.processEvents()
        assert not backend.running
    source = tmp_path / 'реальный файл.txt'
    source.write_text('keep this content', encoding='utf-8')
    backend.addUrls([QUrl.fromLocalFile(str(source))])
    wait()
    assert len(backend.rows) == 1 and not backend.canRun, backend.status
    backend.configure('result_{n:03d}', 1, '', '')
    backend.preview()
    wait()
    assert backend.canRun
    backend.rename()
    wait()
    target = tmp_path / 'result_001.txt'
    assert target.read_text(encoding='utf-8') == 'keep this content'
    assert not source.exists() and backend.canUndo and not backend.canRun
    window.setProperty('page', 2)
    app.processEvents()
    assert backend.history[0]['state'] == 'done'
    backend.undoLast()
    wait()
    assert source.exists() and not target.exists()
    assert backend.history[0]['state'] == 'undone'
    backend.clear()
    assert not backend.rows
    assert not warnings, warnings
    backend.shutdown()
    window.close()
    del window
    del engine
    store.close()
