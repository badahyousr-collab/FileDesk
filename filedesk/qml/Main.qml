import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: win
    width: 1240; height: 800
    minimumWidth: 960; minimumHeight: 650
    visible: true
    title: "pipisso FileDesk"
    color: backend.dark ? "#291f25" : "#e7dee1"
    property color panel: backend.dark ? "#27272c" : "#faf8f9"
    property color ink: backend.dark ? "#f1eef0" : "#252329"
    property color muted: backend.dark ? "#aaa4af" : "#706975"
    property color line: backend.dark ? "#414047" : "#dfd9df"
    property color field: backend.dark ? "#202025" : "#eee9ed"
    property int page: 0
    property bool demo: false
    property int selected: 0
    property var demoRows: [
        {name: "Фото_001.jpg", newName: "catalog_001.jpg", source: "Демонстрационный файл", size: 2400000, status: "Ожидание", error: ""},
        {name: "Каталог.png", newName: "catalog_002.png", source: "Демонстрационный файл", size: 840000, status: "Ожидание", error: ""},
        {name: "Повреждённый.webp", newName: "catalog_003.webp", source: "Демонстрационный файл", size: 12000, status: "Ожидание", error: ""}
    ]
    property var shownRows: demo ? demoRows : backend.rows
    function configure() { backend.configure(pattern.text, Number(start.text || 0), search.text, replacement.text) }
    onClosing: function(close) { if (backend.running) { close.accepted = false; backend.stop() } }
    FileDialog {
        id: picker; title: "Добавить файлы"; fileMode: FileDialog.OpenFiles
        onAccepted: { win.demo = false; backend.addUrls(selectedFiles) }
    }
    FolderDialog {
        id: folderPicker; title: "Добавить папку с вложенными файлами"
        onAccepted: { win.demo = false; backend.addUrls([selectedFolder]) }
    }
    font.family: "Segoe UI"
    font.pixelSize: 14

    component Caption: Label { color: win.muted; font.pixelSize: 12 }
    component Heading: Label { color: win.ink; font.pixelSize: 24; font.weight: Font.DemiBold }
    component Btn: Button {
        id: control
        implicitHeight: 40
        leftPadding: 16; rightPadding: 16
        contentItem: Text { text: control.text; color: control.enabled ? win.ink : win.muted; font: control.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle {
            radius: 10
            color: control.down ? win.line : control.hovered ? (backend.dark ? "#44404a" : "#e1dae1") : win.field
            border.color: control.activeFocus ? "#ba8da1" : win.line
            opacity: control.enabled ? 1 : 0.5
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        ToolTip.visible: hovered && ToolTip.text.length > 0
        ToolTip.delay: 500
    }
    component Input: TextField {
        color: win.ink; selectByMouse: true
        implicitHeight: 42; leftPadding: 12
        placeholderTextColor: win.muted
        background: Rectangle { radius: 9; color: win.field; border.color: parent.activeFocus ? "#ba8da1" : win.line }
    }

    Rectangle {
        anchors.fill: parent; anchors.margins: 14; radius: 20
        color: backend.dark ? "#b31d1d23" : "#b3ffffff"
        border.color: win.line
        ColumnLayout {
            anchors.fill: parent; spacing: 0
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: 66
                Layout.leftMargin: 24; Layout.rightMargin: 24
                Label { text: "pipisso"; color: win.ink; font.pixelSize: 23; font.bold: true }
                Rectangle { width: 1; height: 20; color: win.line; Layout.leftMargin: 8; Layout.rightMargin: 8 }
                Label { text: "FileDesk"; color: win.muted; font.pixelSize: 17 }
                Item { Layout.fillWidth: true }
                Caption { text: "Локально · Без аккаунта" }
                Btn { text: backend.dark ? "☼" : "☾"; ToolTip.text: "Сменить тему"; Accessible.name: "Сменить тему"; onClicked: backend.toggleTheme() }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: win.line }
            RowLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                ColumnLayout {
                    Layout.preferredWidth: backend.collapsed ? 56 : 188
                    Layout.maximumWidth: Layout.preferredWidth
                    Layout.minimumWidth: Layout.preferredWidth
                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 160; easing.type: Easing.InOutQuad } }
                    Layout.fillHeight: true
                    Layout.margins: 12
                    spacing: 8
                    Btn { text: backend.collapsed ? "☰" : "☰   Меню"; Layout.fillWidth: true; font.pixelSize: 12; ToolTip.text: "Свернуть / развернуть меню"; onClicked: backend.toggleSidebar() }
                    Repeater {
                        model: ["Файлы", "Сценарии", "История", "Настройки"]
                        delegate: Btn {
                            required property string modelData
                            required property int index
                            text: backend.collapsed ? ["▤", "◇", "◷", "⚙"][index] : modelData
                            Layout.fillWidth: true
                            highlighted: win.page === index
                            background: Rectangle { radius: 10; color: win.page === index ? (backend.dark ? "#58434f" : "#e7d6df") : (parent.hovered ? win.field : "transparent") }
                            ToolTip.text: modelData
                            Accessible.name: modelData
                            onClicked: win.page = index
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Caption { visible: !backend.collapsed; text: "pipisso FileDesk\nВерсия 0.2"; lineHeight: 1.5; Layout.leftMargin: 12 }
                }
                Rectangle { Layout.fillHeight: true; width: 1; color: win.line }
                ColumnLayout {
                    visible: win.page === 0
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 24; spacing: 18
                    RowLayout {
                        Heading { text: "Ваши файлы" }
                        Item { Layout.fillWidth: true }
                        Btn { text: win.demo ? "Закрыть демо" : "Демо"; enabled: !backend.running; onClicked: { win.demo = !win.demo; win.selected = 0 } }
                        Btn { text: "Очистить"; visible: !win.demo && backend.rows.length > 0; enabled: !backend.running; onClicked: backend.clear() }
                    }
                    Caption { text: "Один порядок действий для всей папки." }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 145
                        radius: 16; color: drop.containsDrag ? (backend.dark ? "#49333e" : "#e7d6df") : win.field; border.color: win.line
                        DropArea {
                            id: drop; anchors.fill: parent; enabled: !backend.running
                            onDropped: function(event) { if (event.hasUrls) { win.demo = false; backend.addUrls(event.urls); event.acceptProposedAction() } }
                        }
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 10
                            Label { text: "Перетащите сюда файлы или папку"; color: win.ink; font.pixelSize: 16; Layout.alignment: Qt.AlignHCenter }
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Btn { text: "Выбрать файлы"; enabled: !backend.running; onClicked: picker.open() }
                                Btn { text: "Выбрать папку"; enabled: !backend.running; onClicked: folderPicker.open() }
                            }
                            Caption { text: "Папки добавляются вместе с вложенными файлами"; Layout.alignment: Qt.AlignHCenter }
                        }
                    }
                    RowLayout {
                        Label { text: win.demo ? "Демонстрационные файлы" : "Список файлов"; color: win.ink; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Caption { text: win.demo ? "3 примера" : backend.rows.length + " файлов" }
                    }
                    Rectangle {
                        Layout.fillHeight: true; Layout.fillWidth: true; radius: 12; color: win.panel; border.color: win.line
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 14; spacing: 8
                            RowLayout {
                                Caption { text: "БЫЛО / СТАНЕТ"; Layout.fillWidth: true }
                                Caption { text: "РАЗМЕР"; Layout.preferredWidth: 65 }
                                Caption { text: "СТАТУС"; Layout.preferredWidth: 90 }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: win.line }
                            ListView {
                                id: files
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                model: win.shownRows
                                ScrollBar.vertical: ScrollBar {}
                                spacing: 6
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: files.width; height: 70; radius: 8
                                    color: win.selected === index ? win.field : "transparent"
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 8
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Label { text: modelData.name; color: win.ink; elide: Text.ElideMiddle; Layout.fillWidth: true }
                                            Caption { text: "→ " + (modelData.newName || "—"); elide: Text.ElideMiddle; Layout.fillWidth: true }
                                        }
                                        Caption { text: modelData.size < 1024 ? modelData.size + " Б" : modelData.size < 1048576 ? (modelData.size / 1024).toFixed(0) + " КБ" : (modelData.size / 1048576).toFixed(1) + " МБ"; Layout.preferredWidth: 65 }
                                        Caption { text: win.demo ? (backend.progress >= 1 ? (index === 2 ? "Ошибка демо" : "Готово демо") : "Ожидание") : modelData.status; wrapMode: Text.WordWrap; color: modelData.error ? "#d88a94" : win.muted; Layout.preferredWidth: 90 }
                                    }
                                    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; onClicked: win.selected = index }
                                    ToolTip.visible: rowMouse.containsMouse
                                    ToolTip.delay: 700
                                    ToolTip.text: modelData.source + (modelData.error ? "\n" + modelData.error : "")
                                }
                                Label { anchors.centerIn: parent; visible: win.shownRows.length === 0; text: "Очередь пока пуста"; color: win.muted }
                            }
                        }
                    }
                }
                Rectangle {
                    visible: win.page === 0
                    Layout.preferredWidth: 285; Layout.fillHeight: true; Layout.margins: 12
                    radius: 15; color: win.panel
                    ScrollView {
                        anchors.fill: parent; anchors.margins: 18; contentWidth: availableWidth; clip: true
                        ColumnLayout {
                            width: parent.width; spacing: 16
                            Label { text: "Параметры"; color: win.ink; font.pixelSize: 18; font.bold: true }
                            Caption { text: "ПАКЕТНОЕ ПЕРЕИМЕНОВАНИЕ" }
                            Caption { text: "Шаблон имени" }
                            Input { id: pattern; text: "{name}"; Layout.fillWidth: true; maximumLength: 200; enabled: !backend.running; onTextEdited: win.configure() }
                            Caption { text: "Первый номер" }
                            Input { id: start; text: "1"; validator: IntValidator { bottom: 1; top: 999999 } Layout.fillWidth: true; enabled: !backend.running; onTextEdited: win.configure() }
                            Caption { text: "{name} — исходное имя\n{n:03d} — номер 001\n{date} — дата изменения"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            Caption { text: "Найти в исходном имени" }
                            Input { id: search; Layout.fillWidth: true; enabled: !backend.running; onTextEdited: win.configure() }
                            Caption { text: "Заменить на" }
                            Input { id: replacement; Layout.fillWidth: true; enabled: !backend.running; onTextEdited: win.configure() }
                            Caption { text: "Расширение сохраняется. Поиск учитывает регистр. Для нумерации: catalog_{n:03d}"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            Btn { text: "Обновить предпросмотр"; enabled: !backend.running && !win.demo && backend.rows.length > 0; Layout.fillWidth: true; onClicked: win.configure() }
                            Btn { text: "Убрать выбранный файл"; enabled: !backend.running && !win.demo && win.selected < backend.rows.length; Layout.fillWidth: true; onClicked: { backend.remove(win.selected); win.selected = 0 } }
                            Caption { text: !win.demo && win.selected < backend.rows.length ? backend.rows[win.selected].error : ""; color: "#d88a94"; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
                            Rectangle { Layout.fillWidth: true; height: 1; color: win.line }
                            Caption { text: "ИЗОБРАЖЕНИЯ · ЭТАП 5" }
                            Caption { text: "Конвертация, размер и качество"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                    }
                }
                ColumnLayout {
                    visible: win.page !== 0
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 32; spacing: 20
                    Heading { text: ["", "Сценарии", "История", "Настройки"][win.page] }
                    Label {
                        text: win.page === 1 ? "Сохранённые цепочки действий появятся на этапе 7." : win.page === 2 ? "Последние 1000 записей. Отмена проверяет содержимое файла и свободное исходное имя." : "Оформление сохраняется между запусками."
                        color: win.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Btn { visible: win.page === 3; text: backend.dark ? "Включить светлую тему" : "Включить тёмную тему"; onClicked: backend.toggleTheme() }
                    ListView {
                        id: historyList; visible: win.page === 2
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
                        model: backend.history
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Rectangle {
                            required property var modelData
                            width: historyList.width; height: historyText.implicitHeight + 24; radius: 10; color: win.panel
                            ColumnLayout {
                                id: historyText; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12
                                Label { text: modelData.source + " → " + modelData.target; color: win.ink; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
                                Caption { text: ({unchanged: "Без изменений", done: "Выполнено", undone: "Отменено", failed: "Ошибка", uncertain: "Нужна ручная проверка", skipped: "Пропущено", pending: "В работе", undoing: "Отмена"})[modelData.state] + " · " + new Date(modelData.created).toLocaleString(); Layout.fillWidth: true }
                                Caption { visible: modelData.error.length > 0; text: modelData.error; color: "#d88a94"; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
                            }
                        }
                    }
                    Item { visible: win.page !== 2; Layout.fillHeight: true }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: win.line }
            RowLayout {
                Layout.fillWidth: true; Layout.margins: 20; spacing: 18
                ColumnLayout {
                    Layout.fillWidth: true
                    Caption { text: backend.status; elide: Text.ElideRight; Layout.fillWidth: true }
                    ProgressBar { visible: win.demo || backend.running; from: 0; to: 1; value: backend.progress; Layout.fillWidth: true; implicitHeight: 5
                        background: Rectangle { radius: 3; color: win.line }
                        contentItem: Item { Rectangle { width: parent.width * backend.progress; height: parent.height; radius: 3; color: "#b48a9e"; Behavior on width { NumberAnimation { duration: 120 } } } }
                    }
                }
                Btn { text: "Остановить"; visible: backend.running; onClicked: backend.stop() }
                Btn { text: "Отменить переименование"; visible: !win.demo; enabled: backend.canUndo; onClicked: backend.undoLast() }
                Btn { text: win.demo ? "Запустить демо" : "Переименовать"; enabled: win.demo ? !backend.running : backend.canRun; onClicked: win.demo ? backend.startDemo() : backend.rename() }
            }
        }
    }
}
