// connect to server
var socket = new WebSocket("ws://localhost:2345");
let id, username;
let loggedIn = false;

socket.onopen = function(event) {
  //socket.send("[msg,Hello!]")
};

socket.onmessage = function(event) {
  console.log(event.data);
  //console.log(event.data.split(',')[0].slice(1));

  if (event.data == "[ntfcn,invalidUser]") {
    document.getElementById("uname").value = "";
    document.getElementById("uname").placeholder = "Username already in use.";
    loggedIn = false;
  } else if (event.data == "[ntfcn,validUser]") {
    document.getElementById("loginform").style = "display: none;";
    document.getElementById("messagingapp").style = "visibility: visible;";
    loggedIn = true;
  }

  if (loggedIn) {
    let header = event.data.split(",")[0].slice(1);
    let data = event.data.split(",")[1];
    data = data.slice(0, data.length - 1);

    if (header == "ID") id = data;
    if (header == "msg") newMessage(data);
    if (header == "ntfcn") {
      if (data == "sameMsg") {
        let input = document.getElementById("input");
        input.value = "";
        input.placeholder = "You just sent that message";
      }
    }
  }
};

socket.onclose = function(event) {
  socket.send("Close");
  newMessage("You have been disconnected from the server!");
  console.log("You have been disconnected from the server!")
};

function login() {
  //let loginform = document.getElementById("loginform");
  //let messagingApp = document.getElementById("messagingapp");
  usernameInput = document.getElementById("uname");
  console.log(usernameInput.value);
  //let password = document.getElementsByName("psw");
  //<label for="psw"><b>Password</b></label>
  //<input type="password" placeholder="Enter Password" name="psw" required>

  if (usernameInput.value.length < 118) {
    socket.send("[uname," + usernameInput.value + "]");
  } else {
    usernameInput.value = "";
    usernameInput.placeholder = "That username is too big!";
  }
}

function newElement() {
  window.scrollTo(0,document.body.scrollHeight);  
  let input = document.getElementById("input");
  if (input.value == "") return;

  if (input.value.length < 120) {
    socket.send("[msg," + input.value + "]");
    input.value = "";
  } else {
    input.value = "";
    input.placeholder = "That message is too big!";
  }
}

document.addEventListener("keyup", function(event) {
    if (event.keyCode === 13) {
        window.scrollTo(0,document.body.scrollHeight);
    }
});

function delFirstMsg() {
  document.getElementById("messages").firstElementChild.remove();
}

function newMessage(message) {
  let mainList = document.getElementById("messages");

  if (mainList.childElementCount >= 100) delFirstMsg();

  let div = document.createElement("div");
  div.className = "message";

  let p = document.createElement("p");
  p.innerText = message;
  div.appendChild(p);

  mainList.appendChild(div);
}
