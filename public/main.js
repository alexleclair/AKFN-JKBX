window.socket = io()
window.socket.on('problem', function(data) {
    console.log('Error!', data);
});

window.socket.on('notification', function(data) {
    console.log('Notification!', data);
});