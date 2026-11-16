import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    implicitWidth: 420
    implicitHeight: root.showLyrics ? 384 : 120
    minWidth: 320
    minHeight: root.showLyrics ? 240 : 100

    Behavior on implicitHeight {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    // ── Configurable Settings from PluginData ──
    property bool showLyrics: (pluginData && pluginData.showLyrics !== undefined) ? pluginData.showLyrics : false
    property bool showVisualizer: (pluginData && pluginData.showVisualizer !== undefined) ? pluginData.showVisualizer : true
    property string lyricAlignment: (pluginData && pluginData.lyricAlignment) ? pluginData.lyricAlignment : "center"
    property string preferredPlayer: (pluginData && pluginData.preferredPlayer) ? pluginData.preferredPlayer : "auto"
    property bool filterDuplicates: (pluginData && pluginData.filterDuplicates !== undefined) ? pluginData.filterDuplicates : true
    property real backgroundOpacity: ((pluginData && pluginData.backgroundOpacity !== undefined) ? pluginData.backgroundOpacity : 85) / 100
    property real borderOpacity: ((pluginData && pluginData.borderOpacity !== undefined) ? pluginData.borderOpacity : 100) / 100
    property string colorMode: (pluginData && pluginData.colorMode) ? pluginData.colorMode : "primary"
    property var customColor: (pluginData && pluginData.customColor) ? pluginData.customColor : Theme.primary
    property bool cookieRotation: (pluginData && pluginData.cookieRotation !== undefined) ? pluginData.cookieRotation : true
    property real cookieRotateSpeed: (pluginData && pluginData.cookieRotateSpeed !== undefined) ? pluginData.cookieRotateSpeed : 5

    // ── Color Theme Resolution ──
    readonly property color activeAccentColor: {
        if (root.colorMode === "secondary") return Theme.secondary;
        if (root.colorMode === "custom" && root.customColor) {
            if (typeof root.customColor === "string") return root.customColor;
            if (root.customColor.valid) return root.customColor;
        }
        return Theme.primary;
    }

    readonly property color cardBgColor: Theme.withAlpha(Theme.surfaceContainerHigh, root.backgroundOpacity)
    readonly property color cardBorderColor: Theme.withAlpha(Theme.outline, root.borderOpacity)

    // ── MPRIS Active Player Tracking ──
    readonly property var playersList: Mpris.players.values
    readonly property MprisPlayer activePlayer: {
        if (!playersList || playersList.length === 0) return null;
        if (root.preferredPlayer !== "auto" && root.preferredPlayer !== "") {
            for (let i = 0; i < playersList.length; i++) {
                let p = playersList[i];
                let identity = p && p.identity ? p.identity : "";
                let desktopEntry = p && p.desktopEntry ? p.desktopEntry : "";
                if (identity.toLowerCase().includes(root.preferredPlayer.toLowerCase()) ||
                    desktopEntry.toLowerCase().includes(root.preferredPlayer.toLowerCase())) {
                    return p;
                }
            }
        }
        for (let i = 0; i < playersList.length; i++) {
            if (playersList[i] && playersList[i].isPlaying) return playersList[i];
        }
        return playersList[0];
    }

    readonly property bool hasActiveMedia: activePlayer && activePlayer.trackTitle && activePlayer.trackTitle.trim().length > 0 && activePlayer.playbackState !== MprisPlaybackState.Stopped
    readonly property bool showNoPlayerNow: !hasActiveMedia

    opacity: showNoPlayerNow ? 0 : 1
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    readonly property string trackTitle: (activePlayer && activePlayer.trackTitle) ? activePlayer.trackTitle : I18n.tr("No Media Playing")
    readonly property string trackArtist: (activePlayer && activePlayer.trackArtist) ? activePlayer.trackArtist : I18n.tr("Unknown Artist")
    readonly property string trackArtUrl: (activePlayer && activePlayer.trackArtUrl) ? activePlayer.trackArtUrl : ""
    readonly property real trackPosition: (activePlayer && activePlayer.position) ? activePlayer.position : 0
    readonly property real trackLength: (activePlayer && activePlayer.length) ? activePlayer.length : 0

    // Cover Art Local Download
    property string artFilePath: ""
    property bool artDownloaded: false
    property int artCacheBuster: 0

    function fetchCoverArt() {
        coverArtDownloader.running = false;

        if (!root.trackArtUrl || root.trackArtUrl.length === 0) {
            root.artDownloaded = false;
            root.artFilePath = "";
            return;
        }
        if (root.trackArtUrl.startsWith("file://")) {
            root.artCacheBuster++;
            root.artFilePath = root.trackArtUrl + (root.trackArtUrl.includes("?") ? "&t=" : "?t=") + root.artCacheBuster;
            root.artDownloaded = true;
            return;
        }

        root.artDownloaded = false;
        root.artFilePath = "";
        let target = "/tmp/dms_cover_" + Qt.md5(root.trackArtUrl) + ".jpg";
        coverArtDownloader.command = [
            "bash", "-c",
            "target=\"$1\"; url=\"$2\"; [ -s \"$target\" ] || { curl -fsSL \"$url\" -o \"$target.tmp.$$\" && mv \"$target.tmp.$$\" \"$target\" || rm -f \"$target.tmp.$$\"; }; [ -s \"$target\" ] && echo \"$target\"",
            "bash", target, root.trackArtUrl
        ];
        coverArtDownloader.running = true;
    }

    onTrackArtUrlChanged: fetchCoverArt()

    Process {
        id: coverArtDownloader
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                let path = data.trim();
                let expected = "/tmp/dms_cover_" + Qt.md5(root.trackArtUrl) + ".jpg";
                if (path !== "" && path === expected) {
                    root.artFilePath = "file://" + path;
                    root.artDownloaded = true;
                }
            }
        }
    }

    // ── Wavy CAVA Audio Visualizer Process ──
    property var cavaPoints: []

    Process {
        id: cavaConfigWriter
        command: [
            "bash", "-c",
            "mkdir -p /tmp/.dankshell && cat > /tmp/.dankshell/cava-matplayer.cfg << 'CAVAEOF'\n" +
            "[general]\n" +
            "bars = 32\n" +
            "framerate = 60\n" +
            "sensitivity = 100\n" +
            "channels = stereo\n" +
            "\n" +
            "[output]\n" +
            "method = raw\n" +
            "channels = stereo\n" +
            "raw_target = /dev/stdout\n" +
            "data_format = ascii\n" +
            "ascii_max_range = 1000\n" +
            "bar_delimiter = 59\n" +
            "frame_delimiter = 10\n" +
            "CAVAEOF"
        ]
        running: false
        onRunningChanged: {
            if (!running) cavaProcess.running = true;
        }
    }

    Process {
        id: cavaProcess
        command: ["cava", "-p", "/tmp/.dankshell/cava-matplayer.cfg"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                if (!line || line.length === 0) return;
                const parts = line.split(";");
                const vals = [];
                for (let i = 0; i < parts.length; i++) {
                    const n = parseInt(parts[i], 10);
                    if (!isNaN(n)) vals.push(n);
                }
                if (vals.length > 0) {
                    root.cavaPoints = vals;
                }
            }
        }
    }

    Component.onCompleted: {
        if (root.showVisualizer) cavaConfigWriter.running = true;
    }

    onShowVisualizerChanged: {
        if (showVisualizer) {
            if (!cavaProcess.running) cavaConfigWriter.running = true;
        } else {
            cavaProcess.running = false;
        }
    }

    // ── Synced Lyrics Engine ──
    property var lyricsLines: []
    property int activeLyricIndex: -1
    property string lyricsStatus: "idle" // "idle", "loading", "ok", "not_found"

    // 300ms Timer syncing track position with lyrics
    Timer {
        id: lyricSyncTimer
        interval: 300
        repeat: true
        running: root.lyricsStatus === "ok" && root.lyricsLines.length > 0 && root.activePlayer && root.activePlayer.isPlaying
        onTriggered: {
            let pos = root.trackPosition;
            let idx = -1;
            for (let i = 0; i < root.lyricsLines.length; i++) {
                if (root.lyricsLines[i].time <= pos) idx = i;
                else break;
            }
            if (idx !== root.activeLyricIndex) {
                root.activeLyricIndex = idx;
            }
        }
    }

    // Python LRCLIB Fetcher Process
    Process {
        id: lyricsProcess
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                let trimmed = data.trim();
                if (trimmed === "not_found" || trimmed === "no_info") {
                    root.lyricsStatus = "not_found";
                    return;
                }
                let parts = trimmed.split("§");
                if (parts.length < 3 || parts[parts.length - 1].trim() !== "ok") {
                    root.lyricsStatus = "not_found";
                    return;
                }
                let lines = [];
                for (let i = 0; i < parts.length - 1; i += 2) {
                    let t = parseFloat(parts[i]);
                    let txt = parts[i + 1] || "";
                    if (!isNaN(t)) lines.push({ time: t, text: txt });
                }
                if (lines.length === 0) {
                    root.lyricsStatus = "not_found";
                    return;
                }
                root.lyricsLines = lines;
                root.activeLyricIndex = -1;
                root.lyricsStatus = "ok";
            }
        }
    }

    function fetchLyrics() {
        lyricsProcess.running = false;
        root.lyricsLines = [];
        root.activeLyricIndex = -1;

        if (!root.activePlayer || !root.trackTitle || root.trackTitle === I18n.tr("No Media Playing")) {
            root.lyricsStatus = "idle";
            return;
        }

        root.lyricsStatus = "loading";
        let scriptPath = Qt.resolvedUrl("./scripts/lyrics.py").toString().replace("file://", "");
        lyricsProcess.command = [
            "python3", scriptPath,
            root.trackTitle, root.trackArtist, String(Math.floor(root.trackLength))
        ];
        lyricsProcess.running = true;
    }

    onTrackTitleChanged: {
        if (root.trackArtUrl.startsWith("file://")) fetchCoverArt();
        fetchLyrics();
    }
    onTrackArtistChanged: fetchLyrics()

    // ── Main Widget Card Container ──
    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.cornerRadius * 1.5
        color: root.cardBgColor
        border.color: root.cardBorderColor
        border.width: 1
        clip: true

        // Strict Mask for Card Rounded Corners
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: card.width
                height: card.height
                radius: card.radius
            }
        }

        // ── Wavy CAVA Audio Visualizer Background ──
        WaveVisualizer {
            id: waveVis
            anchors.fill: parent
            color: root.activeAccentColor
            points: root.cavaPoints
            live: root.showVisualizer && (root.activePlayer ? root.activePlayer.isPlaying : false)
            visible: root.showVisualizer
        }

        Column {
            anchors.fill: parent
            spacing: 0

            // ── Top Main Row (Strictly 120px max height) ──
            Item {
                id: topRow
                width: parent.width
                height: Math.min(120, card.height)

                // Album Art (Strictly Capped Curved Edge Cover Image)
                Rectangle {
                    id: artRect
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    height: Math.min(100, Math.max(40, topRow.height - 20))
                    width: height
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainer
                    clip: true

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: artRect.width
                            height: artRect.height
                            radius: artRect.radius
                        }
                    }

                    Image {
                        anchors.fill: parent
                        source: root.artFilePath
                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        visible: root.artDownloaded && root.artFilePath !== ""
                    }

                    DankIcon {
                        anchors.centerIn: parent
                        name: "music_note"
                        size: Math.min(parent.width * 0.4, 42)
                        color: root.activeAccentColor
                        visible: !root.artDownloaded || root.artFilePath === ""
                    }
                }

                // Center/Right Content Layout: Song Info + Control Pill
                ColumnLayout {
                    anchors {
                        left: artRect.right
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: 14
                        rightMargin: 14
                    }
                    spacing: 4

                    // Artist Name (Top, bold) & Track Title (Bottom)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.trackTitle
                            font.pixelSize: Math.max(14, Math.min(parent.width * 0.05, 17))
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.trackArtist
                            font.pixelSize: Math.max(12, Math.min(parent.width * 0.04, 14))
                            color: Theme.surfaceVariantText
                            opacity: 0.75
                            elide: Text.ElideRight
                        }
                    }

                    // Controls Pill (Right Aligned)
                    Rectangle {
                        id: controlsPill
                        Layout.alignment: Qt.AlignRight
                        implicitWidth: controlsRow.implicitWidth + 12
                        implicitHeight: Math.max(36, Math.min(parent.height * 0.4, 44))
                        radius: 999
                        color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.1)

                        RowLayout {
                            id: controlsRow
                            anchors.centerIn: parent
                            spacing: 4

                            // Synced Lyrics Toggle Button
                            Rectangle {
                                implicitWidth: Math.max(28, Math.min(controlsPill.height * 0.8, 34))
                                implicitHeight: implicitWidth
                                radius: implicitWidth / 2
                                color: root.showLyrics ? root.activeAccentColor : "transparent"

                                DankIcon {
                                    anchors.centerIn: parent
                                    name: "lyrics"
                                    size: Math.max(14, Math.min(parent.width * 0.55, 18))
                                    color: root.showLyrics ? Theme.onPrimary : Theme.surfaceText
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.showLyrics = !root.showLyrics;
                                        if (root.setData) root.setData("showLyrics", root.showLyrics);
                                    }
                                }
                            }

                            // 12-Sided Material Cookie Play/Pause Button
                            MaterialShape {
                                Layout.preferredWidth: controlsPill.height
                                Layout.preferredHeight: controlsPill.height
                                color: root.activeAccentColor
                                shapeMode: "cookie"
                                animated: root.cookieRotation && (root.activePlayer ? root.activePlayer.isPlaying : false)
                                rotateSpeed: root.cookieRotateSpeed

                                DankIcon {
                                    anchors.centerIn: parent
                                    name: (root.activePlayer && root.activePlayer.isPlaying) ? "pause" : "play_arrow"
                                    size: Math.max(18, Math.min(parent.width * 0.5, 24))
                                    color: Theme.onPrimary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.activePlayer && root.activePlayer.togglePlaying) root.activePlayer.togglePlaying();
                                    }
                                }
                            }

                            // Next / Skip Button
                            Rectangle {
                                implicitWidth: Math.max(28, Math.min(controlsPill.height * 0.8, 34))
                                implicitHeight: implicitWidth
                                radius: implicitWidth / 2
                                color: "transparent"

                                DankIcon {
                                    anchors.centerIn: parent
                                    name: "skip_next"
                                    size: Math.max(14, Math.min(parent.width * 0.55, 18))
                                    color: Theme.surfaceText
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.activePlayer && root.activePlayer.next) root.activePlayer.next();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Horizontal Gradient Divider Line ──
            Item {
                width: parent.width
                height: root.showLyrics ? 2 : 0
                visible: root.showLyrics

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.2; color: Theme.surfaceText }
                        GradientStop { position: 0.8; color: Theme.surfaceText }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    opacity: 0.15
                }
            }

            // ── Bottom Synced Lyrics Expandable Container ──
            Item {
                id: lyricsPanel
                width: parent.width
                height: root.showLyrics ? Math.max(0, card.height - topRow.height - 2) : 0
                visible: root.showLyrics && height > 30
                clip: true

                // Loading / Error Status View
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.lyricsStatus !== "ok"
                    spacing: 8

                    DankIcon {
                        Layout.alignment: Qt.AlignHCenter
                        name: root.lyricsStatus === "loading" ? "sync" : "lyrics"
                        size: 28
                        color: root.activeAccentColor

                        SequentialAnimation on rotation {
                            running: root.lyricsStatus === "loading"
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 360; duration: 1000 }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            if (root.lyricsStatus === "loading") return I18n.tr("Fetching Synced Lyrics...");
                            if (root.lyricsStatus === "not_found") return I18n.tr("No Lyrics Found on LRCLIB");
                            return I18n.tr("Play a Track to Load Lyrics");
                        }
                        font.pixelSize: 13
                        color: Theme.surfaceVariantText
                    }
                }

                // Smooth Scrolling Synced Lyrics ListView
                ListView {
                    id: lyricsListView
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    visible: root.lyricsStatus === "ok"
                    clip: true
                    model: root.lyricsLines
                    currentIndex: root.activeLyricIndex >= 0 ? root.activeLyricIndex : 0
                    highlightFollowsCurrentItem: true
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: height * 0.38
                    preferredHighlightEnd: height * 0.62
                    spacing: Math.max(2, Math.min(lyricsPanel.height * 0.02, 8))

                    Behavior on contentY {
                        NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                    }

                    delegate: Item {
                        required property int index
                        required property var modelData
                        width: lyricsListView.width
                        height: Math.max(22, Math.min(lyricsPanel.height * 0.12, 32))

                        readonly property int dist: Math.abs(index - lyricsListView.currentIndex)

                        StyledText {
                            anchors.centerIn: parent
                            width: parent.width
                            horizontalAlignment: {
                                if (root.lyricAlignment === "left") return Text.AlignLeft;
                                if (root.lyricAlignment === "right") return Text.AlignRight;
                                return Text.AlignHCenter;
                            }
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: modelData ? (modelData.text || "♪") : ""

                            font.pixelSize: {
                                let h = lyricsPanel.height;
                                if (dist === 0) return Math.max(14, Math.min(h * 0.075, 17));
                                if (dist === 1) return Math.max(12, Math.min(h * 0.06, 14));
                                if (dist === 2) return Math.max(10, Math.min(h * 0.05, 12));
                                return Math.max(9, Math.min(h * 0.04, 11));
                            }
                            font.weight: dist === 0 ? Font.DemiBold : Font.Normal
                            opacity: {
                                if (dist === 0) return 1.0;
                                if (dist === 1) return 0.65;
                                if (dist === 2) return 0.35;
                                return 0.12;
                            }
                            color: dist === 0 ? root.activeAccentColor : Theme.surfaceText

                            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 250 } }
                        }
                    }
                }
            }
        }
    }
}
