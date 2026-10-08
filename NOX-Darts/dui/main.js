const _DUI_BUILD_KEY = "4f6f7e5e1f41bffc63c207d578fcf43c";

function initDartboard(players) {
    const playerOne = players?.["1"] ?? { name: "Player", points: 0 };
    const playerTwo = players?.["2"] ?? { name: "Practice", points: playerOne.points };

    // Set Names
    document.getElementById('playerOneName').innerText = playerOne.name;
    document.getElementById('playerTwoName').innerText = playerTwo.name;

    // Starting Scores
    if (playerOne.skipScore) { return; }
    document.getElementById('playerOneScores').innerHTML = `<div class="score">${playerOne.points}</div>`;
    document.getElementById('playerTwoScores').innerHTML = `<div class="score">${playerTwo.points}</div>`;
}

function setScore(data) {
    const player = data.player
    if (!player) { console.log("Player Invalid"); return false; }

    const newAmount = data.score
    if (newAmount === undefined || newAmount === null) { console.log("New Score Invalid"); return false; }

    const scoreDiv = document.createElement('div');
    scoreDiv.className = 'score';
    scoreDiv.innerText = newAmount;
    if (player === 1) {
        document.getElementById('playerOneScores').appendChild(scoreDiv);
    } else {
        document.getElementById('playerTwoScores').appendChild(scoreDiv);
    };
}

window.addEventListener("message", e => {
    const item = e.data;
    if(item.event === "startGame") {
        initDartboard(item.payload[0]);
    } else if(item.event === "setScore") {
        setScore(item.payload);
    };
})

document.addEventListener("DOMContentLoaded", () => {
    try {
        const resourceName = typeof GetParentResourceName === "function"
            ? GetParentResourceName()
            : "NOX-Darts";
        fetch(`https://${resourceName}/${resourceName}:duiLoaded`, { method: "POST", body: "{}" });
    } catch(e){}
});


// Initialize with default players
// const players = [
//     { name: "Spayce", score: 0 },
//     { name: "Jordan", score: 0 }
// ];
// initDartboard(players);