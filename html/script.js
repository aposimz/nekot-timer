// NUIメッセージハンドラ
var countdownHideTimer = null;
window.addEventListener('message', function(event) {
    var data = event.data;
    
    switch(data.type) {
        case 'openHostMenu':
            // ホスト設定メニューを表示
            document.getElementById('host-menu').style.display = 'block';
            // 参加者パネル表示
            var panel = document.getElementById('participants-panel');
            if (panel) panel.style.display = 'block';
            
            // 設定値を反映
            document.getElementById('marker-radius').value = data.markerRadius || 10;
            document.getElementById('timer-duration').value = data.timerDuration || 180;
            document.getElementById('countdown-duration').value = data.countdownDuration || 5;
            document.getElementById('countdown-text').value = data.countdownText || "START!";
            if (document.getElementById('end-text')) {
                document.getElementById('end-text').value = data.endText || "Time's Up!";
            }
            break;
            
        case 'updateParticipants':
            // 参加者リストを更新
            updateParticipantsList(data.participants);
            break;
            
        case 'updateCountdown':
            // カウントダウン更新
            var countdownContainer = document.getElementById('countdown');
            var countdownText = document.getElementById('countdown-text-display');
            
            // カウントダウン表示を確実に表示
            countdownContainer.style.display = 'block';
            
            // カウントダウンテキストを更新
            if (data.current !== undefined && data.current !== null) {
                countdownText.textContent = data.current.toString();
                // console.log("Countdown update received: " + data.current);
            } else {
                console.log("Invalid countdown value", data);
            }
            break;
            
        case 'hideCountdown':
            // カウントダウン表示を非表示
            if (countdownHideTimer) {
                clearTimeout(countdownHideTimer);
                countdownHideTimer = null;
            }
            document.getElementById('countdown').style.display = 'none';
            // console.log("Countdown hidden");
            break;
        
        case 'hideTimer':
            // タイマーを非表示
            document.getElementById('timer').style.display = 'none';
            break;
            
        case 'startCountdown':
            // ホストメニューを非表示
            document.getElementById('host-menu').style.display = 'none';
            // 参加者パネルを非表示
            var panel1 = document.getElementById('participants-panel');
            if (panel1) panel1.style.display = 'none';
            
            // カウントダウン開始
            startCountdown(data.duration, data.finalText);
            break;
            
        case 'startTimer':
            // タイマー開始
            startTimer(data.duration);
            // 参加者パネルを非表示（保険）
            var panel2 = document.getElementById('participants-panel');
            if (panel2) panel2.style.display = 'none';
            break;
            
        case 'updateTimer':
            // タイマー更新
            updateTimer(data.remaining);
            break;
            
        case 'timerEnd':
            // タイマー終了
            endTimer();
            break;
    }
});

// 参加者リスト更新
function updateParticipantsList(participants) {
    var list = document.getElementById('participants-list');
    list.innerHTML = '';
    
    if (participants && participants.length > 0) {
        participants.forEach(function(participant) {
            var item = document.createElement('div');
            item.className = 'participant-item';
            item.textContent = participant.name;
            list.appendChild(item);
        });
    } else {
        list.innerHTML = '<div class="no-participants">参加者なし</div>';
    }
}

// カウントダウン開始
function startCountdown(duration, finalText) {
    var countdownContainer = document.getElementById('countdown');
    var countdownText = document.getElementById('countdown-text-display');
    
    // カウントダウン表示
    countdownContainer.style.display = 'block';
    
    // 初期値を設定
    var count = parseInt(duration);
    countdownText.textContent = count.toString(); // 明示的に文字列に変換
    
    // console.log("Countdown started: " + count + "s");
    
    // 初期値が表示されるようにする
    setTimeout(function() {
        // 念のため再度設定
        countdownText.textContent = count.toString();
    }, 50);

}

// タイマー開始
function startTimer(duration) {
    var timerContainer = document.getElementById('timer');
    timerContainer.style.display = 'block';
    
    updateTimer(duration);
}

// タイマー更新
function updateTimer(remaining) {
    var minutes = Math.floor(remaining / 60);
    var seconds = remaining % 60;
    
    var timerText = document.getElementById('timer-text');
    timerText.textContent = (minutes < 10 ? '0' : '') + minutes + ':' + (seconds < 10 ? '0' : '') + seconds;
    
    // 残り時間が少ない場合は色を変える
    if (remaining <= 15) {
        timerText.style.color = '#ff9900';
    }
    if (remaining <= 5) {
        timerText.style.color = '#ff0000';
    }
}

// タイマー終了
function endTimer() {
    var timerContainer = document.getElementById('timer');
    
    // 点滅効果
    var blinkCount = 0;
    var blinkInterval = setInterval(function() {
        timerContainer.style.display = timerContainer.style.display === 'none' ? 'block' : 'none';
        blinkCount++;
        
        if (blinkCount >= 6) {
            clearInterval(blinkInterval);
            timerContainer.style.display = 'none';
        }
    }, 500);
}

// ボタンイベント
document.addEventListener('DOMContentLoaded', function() {
    // 開始ボタン
    document.getElementById('start-button').addEventListener('click', function() {
        var markerRadius = document.getElementById('marker-radius').value;
        var timerDuration = document.getElementById('timer-duration').value;
        var countdownDuration = document.getElementById('countdown-duration').value;
        var countdownText = document.getElementById('countdown-text').value;
        var endText = document.getElementById('end-text') ? document.getElementById('end-text').value : 'END!';
        
        // console.log("Settings: ", {
        //     markerRadius: markerRadius,
        //     timerDuration: timerDuration,
        //     countdownDuration: countdownDuration,
        //     countdownText: countdownText,
        //     endText: endText
        // });
        
        // サーバーにデータを送信
        $.post('https://nekot-timer/startTimer', JSON.stringify({
            markerRadius: parseInt(markerRadius),
            timerDuration: parseInt(timerDuration),
            countdownDuration: parseInt(countdownDuration),
            countdownText: countdownText,
            endText: endText
        }));
    });
    
    // 閉じるボタン
    document.getElementById('close-button').addEventListener('click', function() {
        $.post('https://nekot-timer/closeMenu', JSON.stringify({}));
        document.getElementById('host-menu').style.display = 'none';
        var panel = document.getElementById('participants-panel');
        if (panel) panel.style.display = 'none';
    });

    // 半径変更を即時反映
    var radiusInput = document.getElementById('marker-radius');
    var postRadius = function() {
        var value = parseInt(radiusInput.value);
        if (isNaN(value)) {
            return;
        }
        // console.log("Radius update: ", value);
        $.post('https://nekot-timer/updateRadius', JSON.stringify({
            markerRadius: value
        }));
    };
    radiusInput.addEventListener('input', postRadius);
    radiusInput.addEventListener('change', postRadius);
});
