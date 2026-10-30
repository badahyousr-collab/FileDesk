import QtQuick

Rectangle {
    id: glass
    property bool dark: true
    property bool deep: false
    radius: 26
    color: dark ? "#954649" : "#ead0ce"
    border.color: dark ? "#bd686a" : "#fff1eb"
    border.width: 1
    Canvas {
        anchors.fill: parent
        property bool dark: glass.dark
        property bool deep: glass.deep
        onDarkChanged: requestPaint()
        onDeepChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset(); c.clearRect(0, 0, width, height)
            const r = glass.radius; const w = width; const h = height
            c.beginPath(); c.moveTo(r, 0); c.lineTo(w-r, 0); c.quadraticCurveTo(w,0,w,r)
            c.lineTo(w,h-r); c.quadraticCurveTo(w,h,w-r,h); c.lineTo(r,h); c.quadraticCurveTo(0,h,0,h-r)
            c.lineTo(0,r); c.quadraticCurveTo(0,0,r,0); c.closePath(); c.clip()
            let grad = c.createLinearGradient(0,0,w,h)
            grad.addColorStop(0, dark ? "#96484b" : "#f1d4d0")
            grad.addColorStop(.55, dark ? "#934044" : "#e5bab7")
            grad.addColorStop(1, dark ? "#6e2328" : "#d8b3b4")
            c.fillStyle=grad; c.fillRect(0,0,w,h)
            let shade=c.createRadialGradient(w*.04,h*.03,0,w*.04,h*.03,Math.max(w*.85,h*.40))
            shade.addColorStop(0, dark ? (deep ? "#270000" : "#591e25") : "#ffffff55")
            shade.addColorStop(1,"#00000000"); c.fillStyle=shade; c.fillRect(0,0,w,h)
            let base=c.createRadialGradient(w*.97,h*.97,0,w*.97,h*.97,Math.max(w*.9,h*.30))
            base.addColorStop(0,dark ? (deep ? "#190000" : "#3b0a13") : "#c28c8c")
            base.addColorStop(1,"#00000000"); c.fillStyle=base; c.fillRect(0,0,w,h)
        }
    }
    Rectangle { anchors.fill: parent; radius: glass.radius; color: "transparent"; border.color: glass.border.color; border.width: 1 }
}
