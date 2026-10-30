import QtQuick

Item {
    id: icon
    property string name: "file"
    property color tint: "#fff4f1"
    implicitWidth: 20; implicitHeight: 20
    width: 20; height: 20
    property var paths: ({
        folder: '<path d="M3 7a2 2 0 0 1 2-2h5l2 2h7a2 2 0 0 1 2 2v10H3z"/>',
        file: '<path d="M6 3h8l4 4v14H6zM14 3v5h4M9 12h6M9 16h6"/>',
        history: '<path d="M3 10a9 9 0 1 1 1 7M3 4v6h6M12 7v6l4 2"/>',
        settings: '<path d="m9 3-.5 3-2 .8L4 6l-2 3 2.4 2v2L2 15l2 3 2.5-.8 2 .8.5 3h4l.5-3 2-.8 2.5.8 2-3-2.4-2v-2L22 9l-2-3-2.5.8-2-.8-.5-3z"/><circle cx="12" cy="12" r="3"/>',
        layers: '<path d="m12 3 10 5-10 5L2 8zM2 12l10 5 10-5M2 16l10 5 10-5"/>',
        add: '<path d="M12 5v14M5 12h14"/>',
        chevron: '<path d="m9 5 7 7-7 7"/>',
        down: '<path d="m5 9 7 7 7-7"/>',
        arrow: '<path d="M4 12h16m-6-6 6 6-6 6"/>',
        upload: '<path d="M12 16V3m-5 5 5-5 5 5M4 15v6h16v-6"/>',
        collapse: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16"/>',
        moon: '<path d="M20 15A9 9 0 0 1 9 4a9 9 0 1 0 11 11z"/>',
        sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>',
        play: '<path d="m8 4 12 8-12 8z"/>',
        undo: '<path d="m8 4-5 5 5 5M3 9h10a7 7 0 0 1 0 14"/>',
        trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7"/>',
        check: '<path d="m5 12 4 4L19 6"/>',
        close: '<path d="m6 6 12 12M18 6 6 18"/>',
        info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-11v1"/>',
        warning: '<path d="m12 3 10 18H2zM12 9v5m0 3v1"/>',
        search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>',
        image: '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1"/><path d="m3 17 6-6 4 4 3-3 5 5"/>',
        shield: '<path d="m12 2 8 4v6c0 5-8 10-8 10S4 17 4 12V6zM8 12l3 3 5-6"/>'
    })
    Image { anchors.fill: parent; sourceSize.width: 64; sourceSize.height: 64; fillMode: Image.PreserveAspectFit
    source: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="' + tint + '" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' + (paths[name] || paths.file) + '</svg>')
}
}
