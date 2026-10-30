import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ApplicationWindow {
    id: win
    objectName: "filedeskWindow"
    width: 1320; height: 840
    minimumWidth: 1050; minimumHeight: 700
    visible: true
    title: "pipisso FileDesk"
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    font.family: Qt.platform.os === "osx" ? "SF Pro Display" : "Segoe UI"
    font.pixelSize: 14
    property int page: 0
    property int selected: 0
    property int namingMode: 0
    property bool closeRequested: false
    readonly property bool expanded: !backend.collapsed
    readonly property bool maximized: visibility === Window.Maximized
    readonly property color ink: backend.dark ? "#fff5f1" : "#47212a"
    readonly property color secondary: backend.dark ? "#edc4c0" : "#784e55"
    readonly property color hairline: backend.dark ? "#40ffc7bd" : "#306b2834"
    readonly property color field: backend.dark ? "#35200007" : "#59ffffff"
    readonly property var selectedRow: selected >= 0 && selected < backend.rows.length ? backend.rows[selected] : null
    readonly property string selectedError: selectedRow ? selectedRow.error : ""

    function importFiles(values) {
        const paths = []
        for (let i=0; i<values.length; ++i) paths.push(values[i].toString())
        backend.addPaths(paths)
    }
    function configure() {
        let template = "{name}"
        if (namingMode === 0) template = "{name}_{n:03d}"
        if (namingMode === 1) template = baseName.text.replace(/\{/g,"{{").replace(/\}/g,"}}") + "_{n:03d}"
        backend.configure(template, Number(firstNumber.text || 0), namingMode === 2 ? findText.text : "", namingMode === 2 ? replaceText.text : "")
    }
    function toggleMaximize() { if (maximized) showNormal(); else showMaximized() }
    function sizeText(size) { return size < 1024 ? size + " Б" : size < 1048576 ? (size/1024).toFixed(0) + " КБ" : (size/1048576).toFixed(1) + " МБ" }
    function historyState(state) { return ({done: "Переименован", undone: "Отменено", failed: "Ошибка", uncertain: "Проверьте файл", skipped: "Пропущен", unchanged: "Без изменений", pending: "В работе", undoing: "Отмена"})[state] || state }
    onClosing: function(event) { if (backend.running) { event.accepted=false; closeRequested=true; backend.stop() } }
    Connections {
        target: backend
        function onChanged() { if (win.closeRequested && !backend.running) win.close() }
        function onRowsChanged() { if (win.selected >= backend.rows.length) win.selected = Math.max(0,backend.rows.length-1) }
    }
    Shortcut { sequences: [StandardKey.Open]; enabled: !backend.running; onActivated: backend.chooseFiles() }
    Shortcut { sequences: [StandardKey.Undo]; enabled: backend.canUndo; onActivated: backend.undoLast() }
    Shortcut { sequence: "Ctrl+Shift+O"; enabled: !backend.running; onActivated: backend.chooseFolder() }

    component TextLabel: Label { color: win.ink; elide: Text.ElideRight }
    component Subtext: Label { color: win.secondary; font.pixelSize: 12 }
    component Separator: Rectangle { color: win.hairline; implicitHeight: 1; Layout.fillWidth: true }
    component Action: Button {
        id: action
        property string glyph: ""
        property bool primary: false
        property bool quiet: false
        implicitHeight: 38
        implicitWidth: contentItem.implicitWidth + 28
        leftPadding: 14; rightPadding: 14
        hoverEnabled: true
        opacity: enabled ? 1 : .38
        background: Rectangle {
            radius: 10
            color: action.primary ? (action.down ? "#e9bfb6" : action.hovered ? "#fff5f1" : "#f7e6df") : action.down ? "#45ffffff" : action.hovered ? "#24ffffff" : action.quiet ? "transparent" : "#12ffffff"
            border.width: action.primary || action.quiet ? 0 : 1
            border.color: win.hairline
            Behavior on color { ColorAnimation { duration: 110 } }
            Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 13; color: "transparent"; border.color: action.activeFocus ? win.ink : "transparent" }
        }
        contentItem: RowLayout {
            spacing: 8
            Glyph { visible: action.glyph.length > 0; name: action.glyph; width: 16; height: 16; tint: action.primary ? "#6c2834" : win.ink }
            Label { visible: action.text.length > 0; text: action.text; font.pixelSize: 12; font.weight: action.primary ? Font.DemiBold : Font.Normal; color: action.primary ? "#6c2834" : win.ink; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
        }
        ToolTip.delay: 600
        ToolTip.visible: hovered && ToolTip.text.length > 0
        Accessible.name: text || ToolTip.text
    }
    component Field: TextField {
        id: control
        color: win.ink; selectionColor: "#c78382"; selectedTextColor: "white"
        implicitHeight: 40; leftPadding: 12; rightPadding: 12
        font.pixelSize: 13; selectByMouse: true
        placeholderTextColor: win.secondary
        enabled: !backend.running
        background: Rectangle { color: win.field; radius: 10; border.color: control.activeFocus ? win.ink : win.hairline }
    }
    component Scroller: ScrollBar {
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle { implicitWidth: 4; radius: 2; color: win.secondary; opacity: parent.active ? .65 : .2 }
    }

    Rectangle {
        id: canvas
        anchors.fill: parent; anchors.margins: win.maximized ? 0 : 8
        radius: win.maximized ? 0 : 30
        gradient: Gradient {
            GradientStop { position: 0; color: backend.dark ? "#e9b3b1" : "#f7d9d4" }
            GradientStop { position: .46; color: backend.dark ? "#9b686b" : "#dfb8b7" }
            GradientStop { position: 1; color: backend.dark ? "#290004" : "#bf8e94" }
        }
        border.color: backend.dark ? "#75f5c6be" : "#ccfff2ec"

        // The strip between panels is also a native window drag target.
        MouseArea { anchors.fill: parent; onPressed: win.startSystemMove(); onDoubleClicked: win.toggleMaximize() }
        RowLayout {
            anchors.fill: parent; anchors.margins: 20; spacing: 16
            GlassPanel {
                id: sidebar
                dark: backend.dark; deep: true
                Layout.preferredWidth: win.expanded ? 224 : 66
                Layout.minimumWidth: Layout.preferredWidth; Layout.maximumWidth: Layout.preferredWidth
                Layout.fillHeight: true
                Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.InOutCubic } }
                MouseArea { anchors.fill: parent; onPressed: win.startSystemMove(); onDoubleClicked: win.toggleMaximize() }
                ColumnLayout {
                    anchors.fill: parent; anchors.topMargin: 23; anchors.bottomMargin: 20
                    anchors.leftMargin: win.expanded ? 20 : 8; anchors.rightMargin: win.expanded ? 20 : 8
                    spacing: 0
                    RowLayout {
                        Layout.alignment: Qt.AlignLeft; Layout.leftMargin: win.expanded ? 1 : 4; spacing: win.expanded ? 8 : 4
                        Repeater {
                            model: ["#ff5f57", "#febc2e", "#28c840"]
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                width: win.expanded ? 12 : 10; height: width; radius: width/2; color: modelData
                                Text { anchors.centerIn: parent; visible: dotMouse.containsMouse; text: index === 0 ? "×" : index === 1 ? "−" : "+"; font.pixelSize: 11; color: "#62302b" }
                                MouseArea { id: dotMouse; anchors.fill: parent; anchors.margins: -2; hoverEnabled: true; onClicked: { if(index===0) win.close(); else if(index===1) win.showMinimized(); else win.toggleMaximize() } }
                                ToolTip.visible: dotMouse.containsMouse; ToolTip.text: ["Закрыть", "Свернуть", "Развернуть"][index]
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 30 }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 7
                        TextLabel { text: win.expanded ? "pipisso" : "p."; font.pixelSize: win.expanded ? 27 : 24; font.weight: Font.Bold; Layout.fillWidth: true; horizontalAlignment: win.expanded ? Text.AlignLeft : Text.AlignHCenter }
                        Action { visible: win.expanded; glyph: "collapse"; quiet: true; implicitWidth: 28; leftPadding: 4; rightPadding: 4; ToolTip.text: "Свернуть меню"; onClicked: backend.toggleSidebar() }
                    }
                    Subtext { visible: win.expanded; text: "FileDesk"; font.pixelSize: 13; Layout.topMargin: 2 }
                    Separator { Layout.topMargin: 22; Layout.bottomMargin: 22 }
                    Subtext { visible: win.expanded; text: "РАБОЧЕЕ ПРОСТРАНСТВО"; font.pixelSize: 9; font.letterSpacing: 1.2; Layout.bottomMargin: 12 }
                    Repeater {
                        model: [{title:"Файлы", icon:"folder", page:0}, {title:"История", icon:"history", page:2}, {title:"Сценарии", icon:"layers", page:1}]
                        delegate: AbstractButton {
                            id: nav
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 43
                            hoverEnabled: true
                            Accessible.name: modelData.title
                            objectName: "nav" + modelData.page
                            background: Rectangle {
                                anchors.leftMargin: win.expanded ? -20 : -8; anchors.rightMargin: win.expanded ? -20 : -8
                                anchors.fill: parent
                                gradient: Gradient { orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: win.page===nav.modelData.page ? "#55ffd6d0" : nav.hovered ? "#22ffffff" : "transparent" }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                                Rectangle { visible: win.page===nav.modelData.page; width: 3; height: 23; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; radius: 1; color: "#fff2ec" }
                            }
                            contentItem: RowLayout {
                                spacing: 11
                                Glyph { name: nav.modelData.icon; tint: win.ink; Layout.alignment: Qt.AlignHCenter; Layout.leftMargin: win.expanded ? 3 : 10 }
                                TextLabel { visible: win.expanded; text: nav.modelData.title; font.pixelSize: 13; Layout.fillWidth: true }
                                Glyph { visible: win.expanded && win.page === nav.modelData.page; name: "chevron"; width: 14; height: 14; tint: win.ink }
                            }
                            onClicked: win.page = modelData.page
                            ToolTip.visible: hovered && !win.expanded; ToolTip.text: modelData.title
                        }
                    }
                    Item { Layout.fillHeight: true; Layout.minimumHeight: 30 }
                    Separator { Layout.bottomMargin: 18 }
                    Action { visible: !win.expanded; glyph: "collapse"; quiet: true; Layout.fillWidth: true; leftPadding: 15; ToolTip.text: "Развернуть меню"; onClicked: backend.toggleSidebar() }
                    Action { text: win.expanded ? "Настройки" : ""; glyph: "settings"; quiet: true; Layout.fillWidth: true; ToolTip.text: "Настройки"; onClicked: win.page=3 }
                    Action { text: win.expanded ? (backend.dark ? "Светлая тема" : "Тёмная тема") : ""; glyph: backend.dark ? "sun" : "moon"; quiet: true; Layout.fillWidth: true; ToolTip.text: "Сменить тему"; onClicked: backend.toggleTheme() }
                    Separator { Layout.topMargin: 18; Layout.bottomMargin: 20 }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        Rectangle { width: 30; height: 30; radius: 15; color: "#f4d9a8"; Text { anchors.centerIn: parent; text: "p"; font.bold: true; font.pixelSize: 19; color: "#642630" } }
                        ColumnLayout { visible: win.expanded; spacing: 2
                            TextLabel { text: "Ваше пространство"; font.pixelSize: 11; font.weight: Font.DemiBold }
                            Subtext { text: "Всё остаётся на компьютере"; font.pixelSize: 9 }
                        }
                    }
                }
            }

            GlassPanel {
                id: workspace
                dark: backend.dark
                Layout.fillWidth: true; Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent; spacing: 0
                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: 76
                        MouseArea { anchors.fill: parent; onPressed: win.startSystemMove(); onDoubleClicked: win.toggleMaximize() }
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 27; anchors.rightMargin: 25; spacing: 12
                            ColumnLayout { spacing: 3
                                TextLabel { text: ["Файлы", "Сценарии", "История", "Настройки"][win.page]; font.pixelSize: 22; font.weight: Font.DemiBold }
                                Subtext { text: win.page===0 ? "Порядок начинается с имени" : win.page===2 ? "Выполненные действия и отмена" : win.page===1 ? "Сохранённые последовательности действий" : "Ваш FileDesk"; font.pixelSize: 11 }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle { visible: backend.demo; radius: 7; color: "#26ffffff"; implicitWidth: 53; implicitHeight: 24; TextLabel { anchors.centerIn: parent; text: "ДЕМО"; font.pixelSize: 9; font.letterSpacing: 1 } }
                            Action { objectName: "demoButton"; text: backend.demo ? "Выйти из демо" : "Попробовать демо"; glyph: "play"; quiet: true; enabled: !backend.running; onClicked: backend.setDemo(!backend.demo) }
                        }
                    }
                    Separator { Layout.leftMargin: 26; Layout.rightMargin: 26 }
                    Rectangle {
                        visible: backend.notice.length > 0
                        Layout.fillWidth: true; Layout.margins: 16
                        implicitHeight: noticeText.implicitHeight+24
                        radius: 12; color: "#55431a22"; border.color: win.hairline
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 12
                            Glyph { name: "warning"; tint: win.ink; Layout.alignment: Qt.AlignTop }
                            TextLabel { id: noticeText; text: backend.notice; wrapMode: Text.WrapAnywhere; elide: Text.ElideNone; maximumLineCount: 4; Layout.fillWidth: true; font.pixelSize: 12 }
                            Action { glyph: "close"; quiet: true; implicitWidth: 28; leftPadding: 5; rightPadding: 5; ToolTip.text: "Закрыть сообщение"; onClicked: backend.dismissNotice() }
                        }
                    }
                    RowLayout {
                        visible: win.page===0
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            Layout.margins: 25; spacing: 16
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Action { objectName: "addFilesButton"; text: "Добавить файлы"; glyph: "add"; primary: true; enabled: !backend.running; onClicked: backend.chooseFiles() }
                                Action { objectName: "addFolderButton"; text: "Папку"; glyph: "folder"; enabled: !backend.running; ToolTip.text: "Добавить папку с вложенными файлами"; onClicked: backend.chooseFolder() }
                                Item { Layout.fillWidth: true }
                                Action { glyph: "trash"; quiet: true; implicitWidth: 32; leftPadding: 7; rightPadding: 7; enabled: !backend.running && backend.rows.length>0; ToolTip.text: "Очистить список, не удаляя файлы"; onClicked: backend.clear() }
                            }
                            Rectangle {
                                id: dropZone
                                objectName: "dropZone"
                                Layout.fillWidth: true; Layout.preferredHeight: backend.rows.length ? 74 : 156
                                color: drop.containsDrag ? "#35ffffff" : "#09ffffff"
                                radius: 17; border.color: drop.containsDrag ? win.ink : win.hairline
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }
                                DropArea { id: drop; anchors.fill: parent; enabled: !backend.running
                                    onDropped: function(event) { if(event.hasUrls) { win.importFiles(event.urls); event.acceptProposedAction() } }
                                }
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: 10
                                    Glyph { name: "upload"; width: backend.rows.length ? 20 : 30; height: width; tint: win.secondary; Layout.alignment: Qt.AlignHCenter }
                                    TextLabel { text: backend.rows.length ? "Можно перетащить ещё файлы" : "Перетащите файлы сюда"; font.pixelSize: backend.rows.length ? 11 : 15; Layout.alignment: Qt.AlignHCenter }
                                    Subtext { visible: backend.rows.length===0; text: "или выберите их кнопкой выше"; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                            RowLayout {
                                Subtext { text: "ПРЕДПРОСМОТР"; font.pixelSize: 9; font.letterSpacing: 1.5 }
                                Item { Layout.fillWidth: true }
                                Subtext { text: backend.rows.length + " файлов"; font.pixelSize: 11 }
                            }
                            RowLayout {
                                visible: backend.rows.length > 0; spacing: 8
                                Subtext { text: "Исходное имя / новое имя"; font.pixelSize: 10; Layout.fillWidth: true }
                                Subtext { text: "Размер"; font.pixelSize: 10; Layout.preferredWidth: 54 }
                                Item { Layout.preferredWidth: 20 }
                            }
                            ListView {
                                id: fileList
                                objectName: "fileList"
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                model: backend.rows
                                spacing: 3
                                ScrollBar.vertical: Scroller {}
                                delegate: Rectangle {
                                    id: fileRow
                                    required property var modelData
                                    required property int index
                                    width: fileList.width; height: modelData.error ? 95 : 68
                                    radius: 11
                                    color: win.selected===index ? "#29ffffff" : rowHover.containsMouse ? "#12ffffff" : "transparent"
                                    border.color: modelData.error ? "#e69c8d" : "transparent"
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 10; spacing: 10
                                        Rectangle { width: 30; height: 36; radius: 7; color: "#17ffffff"; Glyph { anchors.centerIn: parent; name: /\.(png|jpe?g|webp)$/i.test(fileRow.modelData.name) ? "image" : "file"; width: 18; height: 18; tint: win.secondary } }
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 5
                                            TextLabel { text: fileRow.modelData.name; font.pixelSize: 12; Layout.fillWidth: true }
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 4
                                                Glyph { name: "arrow"; width: 12; height: 12; tint: win.secondary }
                                                TextLabel { text: fileRow.modelData.newName || "Проверьте параметры"; font.pixelSize: 11; color: win.secondary; Layout.fillWidth: true }
                                            }
                                            Subtext { visible: fileRow.modelData.error.length > 0; text: fileRow.modelData.error; color: backend.dark ? "#ffd4b9" : "#8f2335"; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                                        }
                                        Subtext { text: win.sizeText(fileRow.modelData.size); font.pixelSize: 10; Layout.preferredWidth: 54 }
                                        Glyph { name: fileRow.modelData.error ? "warning" : fileRow.modelData.status === "Готово" ? "check" : fileRow.modelData.status === "Отменено" ? "undo" : "chevron"; width: 16; height: 16; tint: win.secondary }
                                    }
                                    MouseArea { id: rowHover; anchors.fill: parent; hoverEnabled: true; onClicked: win.selected = fileRow.index }
                                    ToolTip.visible: rowHover.containsMouse; ToolTip.delay: 700; ToolTip.text: fileRow.modelData.source + (fileRow.modelData.error ? "\n" + fileRow.modelData.error : "\n" + fileRow.modelData.status)
                                }
                                ColumnLayout {
                                    visible: backend.rows.length===0; anchors.centerIn: parent; spacing: 8
                                    Subtext { text: "Здесь появятся исходные и новые имена"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                                    Subtext { text: "До запуска ничего не изменится"; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                        }
                        Rectangle { Layout.fillHeight: true; width: 1; color: win.hairline; Layout.topMargin: 24; Layout.bottomMargin: 24 }
                        ScrollView {
                            id: inspector
                            Layout.preferredWidth: win.width < 1160 ? 245 : 278; Layout.fillHeight: true
                            contentWidth: availableWidth
                            clip: true
                            ScrollBar.vertical: Scroller {}
                            ColumnLayout {
                                width: inspector.availableWidth - 40; x: 20; y: 25
                                spacing: 13
                                TextLabel { text: "Переименование"; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Subtext { text: "Что изменить в именах файлов?"; font.pixelSize: 11 }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 4
                                    Repeater {
                                        model: ["Добавить номера", "Задать общее имя", "Заменить часть имени"]
                                        delegate: AbstractButton {
                                            id: option
                                            required property string modelData
                                            required property int index
                                            objectName: "namingMode" + index
                                            Layout.fillWidth: true; implicitHeight: 35
                                            enabled: !backend.running
                                            background: Rectangle { radius: 8; color: win.namingMode===option.index ? "#29ffffff" : option.hovered ? "#14ffffff" : "transparent" }
                                            contentItem: RowLayout { spacing: 8
                                                Rectangle { Layout.leftMargin: 9; width: 13; height: 13; radius: 7; color: "transparent"; border.color: win.secondary; Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 3; color: win.ink; visible: win.namingMode===option.index } }
                                                TextLabel { text: option.modelData; font.pixelSize: 11; Layout.fillWidth: true }
                                            }
                                            onClicked: { win.namingMode=index; win.configure() }
                                        }
                                    }
                                }
                                Separator { Layout.topMargin: 5; Layout.bottomMargin: 3 }
                                Subtext { visible: win.namingMode===1; text: "Общее имя"; font.pixelSize: 11 }
                                Field { id: baseName; objectName: "baseName"; visible: win.namingMode===1; text: "Фото"; Layout.fillWidth: true; maximumLength: 150; onTextEdited: win.configure() }
                                Subtext { visible: win.namingMode!==2; text: "Начать нумерацию с"; font.pixelSize: 11 }
                                Field { id: firstNumber; objectName: "firstNumber"; visible: win.namingMode!==2; text: "1"; validator: IntValidator { bottom: 1; top: 999999 } Layout.fillWidth: true; onTextEdited: win.configure() }
                                Subtext { visible: win.namingMode===2; text: "Найти"; font.pixelSize: 11 }
                                Field { id: findText; objectName: "findText"; visible: win.namingMode===2; placeholderText: "Часть исходного имени"; Layout.fillWidth: true; onTextEdited: win.configure() }
                                Subtext { visible: win.namingMode===2; text: "Заменить на"; font.pixelSize: 11 }
                                Field { id: replaceText; objectName: "replaceText"; visible: win.namingMode===2; placeholderText: "Новый текст"; Layout.fillWidth: true; onTextEdited: win.configure() }
                                Subtext { text: win.namingMode===0 ? "К исходному имени добавится _001, _002…" : win.namingMode===1 ? "Например: Фото_001.jpg, Фото_002.jpg" : "Заменяется точное совпадение с учётом регистра."; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 11 }
                                Rectangle {
                                    visible: win.selectedRow !== null
                                    Layout.fillWidth: true; implicitHeight: sampleColumn.implicitHeight+24; radius: 12; color: win.field; border.color: win.hairline
                                    ColumnLayout { id: sampleColumn; anchors.fill: parent; anchors.margins: 12; spacing: 8
                                        Subtext { text: "ПРИМЕР"; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Subtext { text: win.selectedRow ? win.selectedRow.name : ""; elide: Text.ElideMiddle; Layout.fillWidth: true; font.pixelSize: 11 }
                                        Glyph { name: "down"; width: 12; height: 12; tint: win.secondary }
                                        TextLabel { text: win.selectedRow ? win.selectedRow.newName : ""; wrapMode: Text.WrapAnywhere; elide: Text.ElideNone; Layout.fillWidth: true; font.pixelSize: 12 }
                                    }
                                }
                                Subtext { visible: win.selectedError.length>0; text: win.selectedError; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; color: backend.dark ? "#ffd4b9" : "#8f2335"; font.pixelSize: 11 }
                                Action { visible: backend.rows.length>0; text: "Убрать выбранный файл"; glyph: "close"; quiet: true; enabled: !backend.running; Layout.fillWidth: true; onClicked: backend.remove(win.selected) }
                                Separator { Layout.topMargin: 4 }
                                RowLayout { Layout.fillWidth: true; spacing: 8
                                    Glyph { name: "shield"; tint: win.secondary; width: 16; height: 16 }
                                    Subtext { text: "Меняются только имена.\nРасширения и содержимое сохраняются."; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                }
                                Item { Layout.preferredHeight: 30 }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: win.page===2; Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 25; spacing: 17
                        RowLayout {
                            TextLabel { text: backend.demo ? "Демонстрационная история" : "Последние операции"; font.pixelSize: 15; font.weight: Font.DemiBold }
                            Item { Layout.fillWidth: true }
                            Subtext { text: backend.history.length + " записей" }
                        }
                        Subtext { text: backend.demo ? "Примеры остаются только в демо и не меняют настоящую историю." : "Отмена доступна, если файл не изменён и исходное имя свободно."; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        ListView {
                            id: historyList; objectName: "historyList"
                            Layout.fillWidth: true; Layout.fillHeight: true; model: backend.history; clip: true; spacing: 8
                            ScrollBar.vertical: Scroller {}
                            delegate: Rectangle {
                                id: entry
                                required property var modelData
                                width: historyList.width; height: historyText.implicitHeight + 28
                                radius: 13; color: "#17ffffff"; border.color: win.hairline
                                RowLayout { anchors.fill: parent; anchors.margins: 14; spacing: 14
                                    Glyph { name: entry.modelData.state==='undone' ? "undo" : entry.modelData.error ? "warning" : "check"; tint: win.secondary; Layout.alignment: Qt.AlignTop }
                                    ColumnLayout { id: historyText; Layout.fillWidth: true; spacing: 7
                                        RowLayout { Layout.fillWidth: true
                                            TextLabel { text: win.historyState(entry.modelData.state); font.pixelSize: 12; font.weight: Font.DemiBold }
                                            Item { Layout.fillWidth: true }
                                            Subtext { text: new Date(entry.modelData.created).toLocaleString(Qt.locale(), "dd.MM.yyyy  HH:mm"); font.pixelSize: 10 }
                                        }
                                        Subtext { text: entry.modelData.source; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; font.pixelSize: 11 }
                                        TextLabel { text: "→ " + entry.modelData.target; wrapMode: Text.WrapAnywhere; elide: Text.ElideNone; Layout.fillWidth: true; font.pixelSize: 11 }
                                        Subtext { visible: entry.modelData.error.length>0; text: entry.modelData.error; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; color: backend.dark ? "#ffd4b9" : "#8f2335" }
                                    }
                                }
                            }
                            ColumnLayout { visible: backend.history.length===0; anchors.centerIn: parent; spacing: 13
                                Glyph { name: "history"; width: 32; height: 32; tint: win.secondary; Layout.alignment: Qt.AlignHCenter }
                                TextLabel { text: "Пока нет операций"; font.pixelSize: 18; Layout.alignment: Qt.AlignHCenter }
                                Subtext { text: "После переименования здесь появятся все изменения."; Layout.alignment: Qt.AlignHCenter }
                                Action { text: "Перейти к файлам"; Layout.alignment: Qt.AlignHCenter; onClicked: win.page=0 }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: win.page===1; Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 40; spacing: 14
                        Item { Layout.fillHeight: true }
                        Glyph { name: "layers"; width: 36; height: 36; tint: win.secondary; Layout.alignment: Qt.AlignHCenter }
                        TextLabel { text: "Сценарии ещё в разработке"; font.pixelSize: 21; Layout.alignment: Qt.AlignHCenter }
                        Subtext { text: "Здесь можно будет сохранять несколько действий для повторного запуска."; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; Layout.maximumWidth: 390; Layout.alignment: Qt.AlignHCenter }
                        Action { text: "Перейти к переименованию"; Layout.alignment: Qt.AlignHCenter; onClicked: win.page=0 }
                        Item { Layout.fillHeight: true }
                    }
                    ColumnLayout {
                        visible: win.page===3; Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 30; spacing: 20
                        TextLabel { text: "Оформление"; font.pixelSize: 17; font.weight: Font.DemiBold }
                        Subtext { text: "Цвета и стеклянные панели по вашему референсу." }
                        RowLayout { spacing: 10
                            Action { text: "Бордовая тема"; primary: backend.dark; onClicked: { if(!backend.dark) backend.toggleTheme() } }
                            Action { text: "Светлая тема"; primary: !backend.dark; onClicked: { if(backend.dark) backend.toggleTheme() } }
                        }
                        Separator {}
                        TextLabel { text: "Данные и диагностика"; font.pixelSize: 17; font.weight: Font.DemiBold }
                        Subtext { text: "Настройки и история сохраняются на вашем компьютере.\nЖурнал ошибок поможет разобраться, если файл не удалось обработать."; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        Action { text: "Открыть папку данных"; glyph: "folder"; onClicked: backend.openLogs() }
                        Item { Layout.fillHeight: true }
                        Subtext { text: "pipisso FileDesk 0.3 · Работает без аккаунта и интернета" }
                    }
                    Separator { Layout.leftMargin: 26; Layout.rightMargin: 26 }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.margins: 22; spacing: 12
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            ColumnLayout { Layout.fillWidth: true; spacing: 5
                                TextLabel { objectName: "operationStatus"; text: backend.running ? backend.status : backend.actionHint; font.pixelSize: 11; wrapMode: Text.WordWrap; elide: Text.ElideNone; Layout.fillWidth: true }
                                Subtext { visible: backend.demo; text: "Демо не изменяет файлы на компьютере"; font.pixelSize: 10 }
                            }
                            Action { objectName: "undoButton"; text: "Отменить"; glyph: "undo"; enabled: backend.canUndo; ToolTip.text: "Отменить последнее переименование"; onClicked: backend.undoLast() }
                            Action { visible: backend.running; text: "Остановить"; onClicked: backend.stop() }
                            Action { objectName: "renameButton"; visible: !backend.running; text: backend.demo ? "Запустить демо" : "Переименовать"; glyph: "arrow"; primary: true; enabled: backend.canRun; onClicked: backend.rename() }
                        }
                        Rectangle { visible: backend.running; Layout.fillWidth: true; height: 3; radius: 2; color: win.hairline; Rectangle { width: parent.width * backend.progress; height: 3; radius: 2; color: win.ink; Behavior on width { NumberAnimation { duration: 120 } } } }
                    }
                }
            }
        }
    }
    // Native resizing retains the OS drag/snap behavior without a second title bar.
    Repeater {
        model: [Qt.TopEdge|Qt.LeftEdge, Qt.TopEdge, Qt.TopEdge|Qt.RightEdge, Qt.LeftEdge, Qt.RightEdge, Qt.BottomEdge|Qt.LeftEdge, Qt.BottomEdge, Qt.BottomEdge|Qt.RightEdge]
        delegate: MouseArea {
            required property int modelData
            enabled: !win.maximized
            x: (modelData & Qt.LeftEdge) ? 0 : (modelData & Qt.RightEdge) ? win.width-12 : 12
            y: (modelData & Qt.TopEdge) ? 0 : (modelData & Qt.BottomEdge) ? win.height-12 : 12
            width: (modelData & (Qt.LeftEdge|Qt.RightEdge)) ? 12 : win.width-24
            height: (modelData & (Qt.TopEdge|Qt.BottomEdge)) ? 12 : win.height-24
            cursorShape: (modelData=== (Qt.TopEdge|Qt.LeftEdge) || modelData=== (Qt.BottomEdge|Qt.RightEdge)) ? Qt.SizeFDiagCursor : (modelData=== (Qt.TopEdge|Qt.RightEdge) || modelData=== (Qt.BottomEdge|Qt.LeftEdge)) ? Qt.SizeBDiagCursor : (modelData & (Qt.LeftEdge|Qt.RightEdge)) ? Qt.SizeHorCursor : Qt.SizeVerCursor
            onPressed: win.startSystemResize(modelData)
        }
    }
}
