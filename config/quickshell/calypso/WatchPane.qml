// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WATCHTOWER — what is wrong with the passwords you keep, every open
// account at once (calypso/core/audit.py, read in the daemon; only which
// items have which problem comes here): a card for each kind of problem,
// how many items have it, what it means. A card is the list of those
// items. The breach check is asked for, never run on its own: it asks Have
// I Been Pwned with five characters of each password's hash, and nothing
// more.

import QtQuick
import "../morpheus"
import "../terminus"
import "calypso.js" as C

Item {
  id: watch
  property var win: null
  readonly property var mgr: watch.win ? watch.win.mgr : null
  readonly property var counts: {
    const out = {};
    if (!watch.mgr) return out;
    for (const k in watch.mgr.flags)
      for (const p of watch.mgr.flags[k]) out[p] = (out[p] || 0) + 1;
    return out;
  }
  // "no one-time password" is a hint, not a problem (which sites offer
  // two-factor is not known here): it is not counted among those to look at
  readonly property int total: {
    let n = 0;
    const f = watch.mgr ? watch.mgr.flags : {};
    for (const k in f) if (f[k].some((p) => p !== "no2fa")) n++;
    return n;
  }
  readonly property bool checked: !!watch.mgr && Object.keys(watch.mgr.audits).length > 0
  readonly property bool breachChecked: {
    if (!watch.mgr) return false;
    for (const id in watch.mgr.audits) if (watch.mgr.audits[id] && watch.mgr.audits[id].pwnedAt) return true;
    return false;
  }
  property bool askedBreach: false

  function run(pwned) {
    watch.askedBreach = !!pwned;
    watch.mgr.audit(pwned, (ok, err) => {
      if (!ok) watch.win.failed(err, null);
      else if (pwned) watch.win.say(watch.counts.pwned ? watch.counts.pwned + " passwords seen in breaches" : "None of your passwords is in a known breach");
    });
  }
  onVisibleChanged: if (visible && !watch.checked && watch.mgr && watch.mgr.anyOpen && !watch.mgr.auditing) watch.run(false)

  Flickable {
    id: flick
    anchors.fill: parent
    contentHeight: col.implicitHeight + 60
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: col
      x: Math.max(28, (flick.width - width) / 2)
      y: 28
      width: Math.min(flick.width - 56, 860)
      spacing: 22

      Row {
        spacing: 18
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: watch.total === 0 && watch.checked ? "\u{F0565}" : "\u{F0ECC}"
          color: watch.total === 0 && watch.checked ? Zenon.green : Zenon.yellow
          font.family: Zenon.glyphFace
          font.pixelSize: 54
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          Text {
            text: !watch.checked ? "Looking over your passwords…"
              : watch.total === 0 ? "Nothing to worry about" : watch.total + (watch.total === 1 ? " item needs" : " items need") + " a look"
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(24)
          }
          Text {
            text: "Every open account, read here on this machine — nothing about your passwords leaves it"
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
        }
      }

      Grid {
        id: grid
        width: parent.width
        columns: width > 700 ? 3 : 2
        columnSpacing: 12
        rowSpacing: 12
        readonly property real cellW: (width - (columns - 1) * columnSpacing) / columns
        Repeater {
          model: C.PROBLEMS
          delegate: Rectangle {
            id: card
            required property var modelData
            readonly property int n: watch.counts[modelData.id] || 0
            readonly property bool open: modelData.id !== "pwned" || watch.breachChecked
            width: grid.cellW
            height: 128
            radius: Zenon.rad(11)
            color: press.pressed ? Zenon.pressWash(0.12) : Zenon.wash(0.04)
            border.width: 1
            border.color: card.n > 0 ? Zenon.alpha(Zenon[modelData.ink] || Zenon.accentMuted, 0.5) : Zenon.border
            Column {
              x: 16
              y: 14
              width: parent.width - 32
              spacing: 4
              Text {
                text: !card.open ? "—" : String(card.n)
                color: card.n > 0 ? (Zenon[card.modelData.ink] || Zenon.ink) : Zenon.green
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(26)
                font.features: { "tnum": 1 }
              }
              Text {
                text: card.modelData.label
                color: Zenon.ink
                font.family: Zenon.face
                font.weight: Font.DemiBold
                font.pixelSize: Zenon.px(15)
              }
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: card.modelData.say
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(12)
              }
            }
            MouseArea {
              id: press
              anchors.fill: parent
              enabled: card.n > 0
              onClicked: watch.win.setScope({ shelf: "watch", audit: card.modelData.id, acct: watch.win.scope.acct })
            }
          }
        }
      }

      // the breach check: asked for, and said what it sends
      Rectangle {
        width: parent.width
        height: breachCol.implicitHeight + 32
        radius: Zenon.rad(11)
        color: Zenon.wash(0.04)
        border.width: 1
        border.color: Zenon.border
        Column {
          id: breachCol
          x: 18
          y: 16
          width: parent.width - 36
          spacing: 12
          Text {
            text: "Breached passwords"
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(15)
          }
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "Asks Have I Been Pwned whether each password has turned up in a breach. Only the first five characters of each password's SHA-1 hash are sent; the answer is compared here, so neither a password nor its whole hash ever leaves this machine."
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
          Row {
            spacing: 8
            BusyButton {
              label: watch.breachChecked ? "Check again" : "Check for breaches"
              ink: Zenon.cyan
              primary: true
              busy: !!watch.mgr && watch.mgr.auditing && watch.askedBreach
              busyText: "Asking…"
              ready: !!watch.mgr && watch.mgr.anyOpen
              onClicked: watch.run(true)
            }
            BusyButton {
              label: "Look again"
              busy: !!watch.mgr && watch.mgr.auditing && !watch.askedBreach
              busyText: "Reading…"
              ready: !!watch.mgr && watch.mgr.anyOpen
              onClicked: watch.run(false)
            }
          }
        }
      }
    }
  }
  ElasticScroll { anchors.fill: flick; view: flick }
  Scrollbar { flick: flick; anchors.right: flick.right; anchors.top: flick.top; anchors.bottom: flick.bottom }
}
