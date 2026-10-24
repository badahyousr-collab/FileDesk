from filedesk.settings import Settings


def test_settings_survive_restart(tmp_path):
    path = tmp_path / "nested" / "settings.sqlite3"
    store = Settings(path)
    assert store.get("theme", "dark") == "dark"
    store.set("theme", "light")
    store.set("theme", "dark")
    store.set("collapsed", "true")
    store.close()
    reopened = Settings(path)
    assert reopened.get("theme", "light") == "dark"
    assert reopened.get("collapsed", "false") == "true"
    reopened.close()
