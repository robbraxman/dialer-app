/*
 * Copyright 2012-2013 Canonical Ltd.
 *
 * This file is part of dialer-app.
 *
 * dialer-app is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * dialer-app is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.0
import Ubuntu.Components 1.1
import Ubuntu.Components.ListItems 0.1 as ListItems
import Ubuntu.Components.Popups 0.1
import Ubuntu.Telephony 0.1
import Ubuntu.Contacts 0.1
import QtContacts 5.0
import "../DialerPage"
import "../"

Page {
    id: liveCall
    objectName: "pageLiveCall"

    property var call: callManager.foregroundCall
    property var calls: callManager.calls
    property string dtmfEntry: ""
    property alias number: contactWatcher.identifier
    property bool onHold: call ? call.held : false
    property bool isMuted: call ? call.muted : false
    property bool dtmfVisible: call ? call.voicemail : false
    property bool multiCall: callManager.calls.length > 1
    property bool isVoicemail: (call ? call.voicemail : false) && callManager.calls.length === 1
    property string activeAudioOutput: call ? call.activeAudioOutput : ""
    property variant audioOutputs: call ? call.audioOutputs : null
    property string phoneNumberSubTypeLabel: ""
    property int defaultTimeout: 10000
    property string initialStatus: ""
    property string initialNumber: ""
    property string caller: {
        if (call && call.isConference) {
            return i18n.tr("Conference");
        } else if (contactWatcher.alias !== "") {
            return contactWatcher.alias;
        } else if (contactWatcher.identifier !== "") {
            return contactWatcher.identifier;
        } else if (!call && initialNumber != "") {
            return initialNumber
        } else {
            return " "
        }
    }

    property Action backAction: Action {
        id: backAction
        objectName: "backButton"
        iconName: "back"
        onTriggered: {
            if (mainView.greeterMode) {
               greeter.showGreeter();
            } else {
                pageStackNormalMode.pop();
            }
        }
    }

    title: caller
    head.actions: []
    head.backAction: backAction
    head.sections.model: multipleAccounts ? [call.account.displayName] : undefined
    x: header ? header.height : 0

    function reportStatus(callObject, text) {
        // if a previous status was already set, do not overwrite it
        if (statusLabel.text !== "" || callManager.hasCalls) {
            return;
        }
        statusLabel.text = text;
        callConnection.target = null;
        liveCall.call = callObject;
        liveCall.dtmfVisible = false;
        closeTimer.running = true;
    }

    function isDefaultAudioOutput(id) {
        return (id == "default" ||
                id == "wired_headset" ||
                id == "earpiece")
    }

    function changeCallHoldingStatus(call, held) {
        callHoldingConnection.target = call;
        call.held = held;
    }

    Connections {
        target: callManager
        onHasCallsChanged: {
            if(!callManager.hasCalls) {
                reportStatus({}, i18n.tr("No calls"));
            } else {
                closeTimer.running = false;
                statusLabel.text = "";
                liveCall.call = Qt.binding(callManager.foregroundCall);
            }
        }

        onConferenceRequestFailed: {
            mainView.showNotification(i18n.tr("Conference call failure"),
                                      i18n.tr("Failed to create a conference call."));
        }
    }

    Connections {
        id: callConnection
        target: call
        onCallEnded: {
            var callObject = {};
            callObject["elapsedTime"] = call.elapsedTime;
            callObject["active"] = true;
            callObject["voicemail"] = call.voicemail;
            callObject["account"] = call.account;
            callObject["phoneNumber"] = call.phoneNumber;
            callObject["held"] = call.held;
            callObject["muted"] = call.muted;
            callObject["activeAudioOutput"] = call.activeAudioOutput;
            callObject["audioOutputs"] = [];
            callObject["isConference"] = call.isConference;

            reportStatus(callObject, i18n.tr("Call ended"));
        }
    }

    Connections {
        id: callHoldingConnection
        // the target will be set on the actions
        onCallHoldingFailed: {
            mainView.showNotification(i18n.tr("Call holding failure"),
                                      target.held ? i18n.tr("Failed to activate the call.")
                                                  : i18n.tr("Failed to place the active call on hold."));
        }
    }

    Component {
        id: audioOutputsPopover
        Popover {
            id: popover
            Column {
                id: containerLayout
                anchors {
                    left: parent.left
                    top: parent.top
                    right: parent.right
                }
                ListItems.Header { text: i18n.tr("Switch audio source:") }
                Repeater {
                    model: audioOutputs
                    ListItems.Standard {
                        text: nameForAudioId(modelData.id)
                        showDivider: index != model.count-1
                        onClicked: {
                            call.activeAudioOutput = modelData.id
                            PopupUtils.close(popover)
                        }
                    }
                }
            }
        }
    }

    states: [
        State {
            name: "keypadVisible"
            when: dtmfVisible

            PropertyChanges {
                target: durationLabel
                anchors.topMargin: units.gu(3)
            }

            PropertyChanges {
                target: callerLabel
                font.pixelSize: FontUtils.sizeToPixels("small")
            }

            PropertyChanges {
                target: keypad
                opacity: 1.0
            }
            PropertyChanges {
                target: liveCall
                title: ""
            }
            PropertyChanges {
                target: dtmfButton
                iconColor: UbuntuColors.green
            }
        },

        State {
            name: "multiCall"
            when: (multiCall || call && call.isConference) && !dtmfVisible

            PropertyChanges {
                target: durationLabel
                opacity: 0.0
            }

            PropertyChanges {
                target: callerLabel
                opacity: 0.0
            }

            PropertyChanges {
                target: multiCallArea
                opacity: 1.0
            }
        },

        State {
            name: "closing"
            when: closeTimer.running || greeterAnimationTimer.running

            PropertyChanges {
                target: buttonsArea
                opacity: 0.0
                enabled: false
            }

            PropertyChanges {
                target: hangupButton
                enabled: false
            }

            PropertyChanges {
                target: durationLabel
                anchors.topMargin: units.gu(9)
            }
        }
    ]

    transitions: [
        Transition {
            ParallelAnimation {
                UbuntuNumberAnimation {
                    targets: [durationLabel,callerLabel]
                    properties: "font.pixelSize,anchors.topMargin,opacity"
                }
                UbuntuNumberAnimation {
                    targets: [keypad,multiCallArea,buttonsArea]
                    properties: "opacity"
                }
            }
        }

    ]

    onCallChanged: {
        // reset the DTMF keypad visibility status
        dtmfVisible = (call && call.voicemail);
    }

    onActiveChanged: {
        callManager.callIndicatorVisible = !active && callManager.hasCalls;
    }

    Component.onCompleted: {
        callManager.callIndicatorVisible = !active && callManager.hasCalls;
    }

    Timer {
        id: callWatcher
        interval: defaultTimeout
        repeat: false
        running: true
        onTriggered: {
            if (!callManager.hasCalls) {
                // TODO: notify about failed call
                reportStatus({}, i18n.tr("Call failed"))
            }
        }
    }

    Timer {
        id: greeterAnimationTimer
        interval: 1000
        repeat: false
        running: false
        onTriggered: mainView.switchToKeypadView()
    }
 
    Timer {
        id: closeTimer
        interval: mainView.greeterMode ? 2000 : 3000
        repeat: false
        running: false
        onTriggered: {
            if (!callManager.hasCalls) {
                if (!mainView.greeterMode) {
                    mainView.switchToKeypadView();
                }

                // TODO: we can't be sure that the currentPage is a DialerPage instance
                if (pageStackNormalMode.currentPage.dialNumber) {
                    pageStackNormalMode.currentPage.dialNumber = pendingNumberToDial;
                }
                if (mainView.greeterMode) {
                    greeter.showGreeter();
                    greeterAnimationTimer.running = true
                }
            }
        }
    }

    function endCall() {
        if (call) {
            call.endCall();
        }
    }

    function nameForAudioId(id) {
        if (id == "bluetooth") {
            return i18n.tr("Bluetooth device")
        } else if (id == "default") {
            return i18n.tr("Ubuntu Phone")
        } else if (id == "speaker") {
            return i18n.tr("Phone Speaker")
        }
        return i18n.tr("Unknown device")
    }

    Image {
        id: background
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        source: Qt.resolvedUrl("../assets/dialer_background_full.png")
        asynchronous: true
    }

    // FIXME: this invisible label is only used for
    // calculating the size of the screen and resizing
    // the dtmf string accordingly so it can fit the page header
    Label {
        id: dtmfLabelHelper
        visible: false
        text: dtmfEntry
        anchors.left: parent.left
        anchors.leftMargin: units.gu(2)
        anchors.right: parent.right
        anchors.rightMargin: units.gu(4)
        fontSize: "x-large"
        onTextChanged: {
            if(paintedWidth > width) {
                // drop the first number
                dtmfEntry = dtmfEntry.substr(1)
            }
        }
    }

    Item {
        id: helper
        function updateSubTypeLabel() {
            phoneNumberSubTypeLabel = contactWatcher.isUnknown ? "": phoneTypeModel.get(phoneTypeModel.getTypeIndex(phoneDetail)).label
        }
        Component.onCompleted: updateSubTypeLabel()

        ContactWatcher {
            id: contactWatcher
            // FIXME: handle conf calls
            identifier: call ? call.phoneNumber : ""
            onDetailPropertiesChanged: helper.updateSubTypeLabel()
            onIsUnknownChanged: helper.updateSubTypeLabel()
            // FIXME: if we implement VOIP, get the addressable fields from the account itself
            addressableFields: ["tel"]
        }


        PhoneNumber {
            id: phoneDetail
            contexts: contactWatcher.detailProperties.phoneNumberContexts
            subTypes: contactWatcher.detailProperties.phoneNumberSubTypes
        }

        ContactDetailPhoneNumberTypeModel {
            id: phoneTypeModel
            Component.onCompleted: helper.updateSubTypeLabel()
        }
    }

    StopWatch {
        id: stopWatch
        objectName: "stopWatch"
        time: call ? call.elapsedTime : 0
    }

    Item {
        id: centralArea
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: buttonsArea.top
        }

        Label {
            id: statusLabel
            anchors {
                bottom: durationLabel.top
                bottomMargin: units.gu(1)
                horizontalCenter: durationLabel.horizontalCenter
            }
            text: ""
            fontSize: "large"
            opacity: text !== "" ? 1 : 0

            Behavior on opacity {
                UbuntuNumberAnimation { }
            }
        }

        Label {
            id: durationLabel

            anchors {
                top: parent.top
                topMargin: units.gu(5)
                horizontalCenter: parent.horizontalCenter
            }
            horizontalAlignment: Qt.AlignHCenter
            width: units.gu(11)
            text: {
                if (dtmfVisible && dtmfLabelHelper.text !== "") {
                    return dtmfLabelHelper.text;
                } else if (call && call.active) {
                    // TRANSLATORS: %1 is the call duration here.
                    return call.held ? i18n.tr("%1 - on hold").arg(stopWatch.elapsed) : stopWatch.elapsed;
                } else if (call && !call.incoming) {
                    return i18n.tr("Calling")
                } else if (!call && initialStatus !== "") {
                    return initialStatus
                } else {
                    return " "
                }
            }
            fontSize: "x-large"
        }

        Label {
            id: callerLabel

            anchors {
                top: durationLabel.bottom
                topMargin: units.gu(1)
                horizontalCenter: parent.horizontalCenter
            }
            text: caller
            fontSize: "large"
            color: UbuntuColors.lightAubergine
        }

        MultiCallDisplay {
            id: multiCallArea
            objectName: "multiCallDisplay"
            calls: callManager.calls
            opacity: 0
            anchors {
                fill: parent
            }
        }

        ListItems.ThinDivider {
            id: divider
            opacity: keypad.opacity
            anchors {
                left: parent.left
                right: parent.right
                top: callerLabel.bottom
                topMargin: units.gu(2)
            }
        }

        Keypad {
            id: keypad

            anchors {
                top: divider.bottom
                topMargin: units.gu(2)
                horizontalCenter: parent.horizontalCenter
            }
            onKeyPressed: {
                if (call) {
                    dtmfEntry += keychar
                    call.sendDTMF(keychar)
                }
            }

            visible: opacity > 0.0
            opacity: 0.0
        }
    }

    Row {
        id: multiCallActionArea

        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: buttonsArea.top
            bottomMargin: units.gu(2)
        }

        width: childrenRect.width
        height: swapButton.height
        opacity: multiCall && !dtmfVisible ? 1 : 0
        enabled : opacity > 0
        spacing: units.gu(3)

        Behavior on opacity {
            UbuntuNumberAnimation { }
        }

        Button {
            id: swapButton
            visible: calls.length > 1
            anchors {
                verticalCenter: parent.verticalCenter
            }

            text: i18n.tr("Switch calls")
            color: mainView.backgroundColor
            strokeColor: UbuntuColors.green
            onClicked: {
                changeCallHoldingStatus(callManager.foregroundCall, true)
            }
        }

        Button {
            id: mergeButton
            visible: calls.length > 1
            anchors {
                verticalCenter: parent.verticalCenter
            }

            text: i18n.tr("Merge calls")
            color: mainView.backgroundColor
            strokeColor: UbuntuColors.green
            onClicked: {
                callManager.mergeCalls(callManager.calls[0], callManager.calls[1])
            }
        }
    }

    Row {
        id: buttonsArea

        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: footer.top
            bottomMargin: units.gu(1)
        }

        height: childrenRect.height
        width: childrenRect.width

        LiveCallKeypadButton {
            id: speakerButton
            objectName: "speakerButton"
            iconSource: {
                if (audioOutputs && audioOutputs.length <= 2) {
                    if (activeAudioOutput == "speaker") {
                        return "speaker"
                    }
                    return "speaker-mute"
                } else {
                    if (activeAudioOutput == "bluetooth") {
                        return "audio-speakers-bluetooth-symbolic"
                    } else if (activeAudioOutput == "speaker") {
                        return "speaker"
                    } else {
                        return "speaker-mute"
                    }
                }
            }
            selected: !isDefaultAudioOutput(activeAudioOutput)
            iconWidth: units.gu(3)
            iconHeight: units.gu(3)
            onClicked: {
                if (call) {
                    // all phones have at least two outputs: speaker and default,
                    // where default is either earpiece or wired headset
                    // if we have more than 2, we have to show a popup so users
                    // can select the active audio output
                    if (audioOutputs.length > 2) {
                        PopupUtils.open(audioOutputsPopover, speakerButton)
                        return
                    }
                    if (isDefaultAudioOutput(call.activeAudioOutput)) {
                        call.activeAudioOutput = "speaker"
                    } else {
                        call.activeAudioOutput = "default"
                    }
                }
            }
        }

        LiveCallKeypadButton {
            objectName: "muteButton"
            iconSource: selected ? "microphone-mute" : "microphone"
            enabled: !isVoicemail
            selected: liveCall.isMuted
            iconWidth: units.gu(3)
            iconHeight: units.gu(3)
            onClicked: {
                if (call) {
                    call.muted = !call.muted
                }
            }
        }

        LiveCallKeypadButton {
            id: newCallButton
            objectName: "newCallButton"
            iconSource: "add"
            iconWidth: units.gu(3)
            iconHeight: units.gu(3)
            enabled: !mainView.greeterMode
            onClicked: pageStackNormalMode.push(Qt.resolvedUrl("../ContactsPage/ContactsPage.qml"))
        }

        LiveCallKeypadButton {
            objectName: "callHoldButton"
            iconSource: {
                if (callManager.backgroundCall) {
                    return "swap"
                } else if (selected) {
                    return "media-playback-start"
                } else {
                    return "media-playback-pause"
                }
            }
            selected: liveCall.onHold
            iconWidth: units.gu(3)
            iconHeight: units.gu(3)
            onClicked: {
                if (call) {
                    changeCallHoldingStatus(call, !call.held)
                }
            }
        }

        LiveCallKeypadButton {
            id: dtmfButton
            objectName: "dtmfButton"
            iconSource: "keypad"
            iconWidth: units.gu(4)
            iconHeight: units.gu(4)
            enabled: !isVoicemail
            onClicked: dtmfVisible = !dtmfVisible
        }
    }

    Item {
        id: footer
        height: units.gu(10)
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }

        HangupButton {
            id: hangupButton
            objectName: "hangupButton"

            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: units.gu(5)
            }
            onClicked: endCall()
        }
    }
}
