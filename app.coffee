fs = require('fs')
App = 
	config:
		http:
			port:8090
			host:'0.0.0.0'
		songs:
			path:'/Users/stax/Music/iTunes/iTunes Music'
			# path:'/Users/stax/Desktop/songs'
			watch:true
			addWaitTime:3 #ms
		client:
			requireLogin:false
			allowAnonymous:true

	express:require('express')
	io:null
	app:null
	server:null
	fs:require('fs')
	chokidar:require('chokidar');
	watcher:null
	lastAdd:0
	songs:{}
	playlist:[]
	mm: require('musicmetadata');
	_player: require('player')
	player:null
	isPlaying:false
	codes:{}

	init:(config)->
		App.config = config

		App.codes = require('./codes.json')

		App.app = App.express()
		App.server = require('http').createServer(App.app);
		App.io = require('socket.io')(App.server);

		App.server.listen App.config.http.port;
		App.app.use App.express.static(__dirname + '/dist');
		
		App.io.on 'connection', App.onConnect
		Player = require('player');
		
		App.watcher = App.chokidar.watch(App.config.songs.path, {ignored: /[\/\\]\./, persistent: true, interval:2000, binaryInterval:3000, usePolling:true});
		App.watcher.on 'add', (path)->
			App.addSong path
		App.watcher.on 'change', (path)->
			App.addSong path
		App.watcher.on 'unlink', (path)->
			console.log 'Removed song', path
			App.io.emit 'removeSong', path
			delete App.songs[path]


	play:()->
		if App.playlist.length == 0
				_songs = []
				for key of App.songs
					_songs.push key
				song = App.songs[_songs[Math.floor(Math.random()*_songs.length)]]
			else
				song = App.playlist.shift()
			if !song?
				return;
			path = song.path+'';
			console.log 'Playing song', path, song
			App.io.emit 'playlist', App.playlist
			App.io.emit 'playing', song
			App.currentSong = song

			setTimeout ->
				if App.player?
					App.player.stop()
				App.player = new App._player(path);
				App.player.on 'playend', ->
					App.play()
				App.player.on 'error', ->
					App.play()

				App.player.play();

				App.isPlaying= true;
			, 1000

	addSong:(file, wait=true, addTime=2000)->
		waitTime = 0;
		if wait
			_now = Date.now()
			App.lastAdd = if App.lastAdd > _now then App.lastAdd + App.config.songs.addWaitTime else _now + App.config.songs.addWaitTime
			waitTime = App.lastAdd - _now;
		if waitTime < 0
			waitTime = 0;
		if wait
			waitTime = waitTime + addTime
		setTimeout ->
			try

				stream = fs.createReadStream(file);
				stream.on 'error', ()->
					console.log 'error?', arguments
				parser = App.mm(stream);
				parser.on 'metadata', (result)->
					song = {
						title:result.title
						album:result.album
						artist:result.artist
						path:file
					}
					App.songs[file] = song
					App.io.emit 'addSong', song,file
					console.log 'added',file

				parser.on 'done', ()->
					stream.destroy();
				parser.on 'error', ()->
					stream.destroy();
			catch e
				# ...
			
		, waitTime

	walk: (dir, done) ->
		results = []
		fs.readdir dir, (err, list) ->
			return done(err)  if err
			i = 0
			(next = ->
				file = list[i++]
				return done(null, results)  unless file
				file = dir + "/" + file
				fs.stat file, (err, stat) ->
					if stat and stat.isDirectory()
						App.walk file, (err, res) ->
							results = results.concat(res)
							next()
							return

					else
						results.push file
						next()
					return

				return
			)()
			return

		return


	onConnect:(socket)->
		isAuthenticated = false;
		code= if App.config.client.allowAnonymous then 'anonymous' : null;

		socket.emit 'config', App.config.client;
		socket.emit 'songs', App.songs;
		socket.emit 'playlist', App.playlist
		socket.emit 'playing', App.currentSong

		socket.on 'login',  (data)->
			console.log 'hey', 'code', data
			if isAuthenticated
				return App.sendError socket, 'Already logged in!'

			if !data? || !data.code
				return App.sendError socket, 'Missing code'

			if !App.codes[data.code]?
				return App.sendError socket, 'Invalid code'

			isAuthenticated = true;
			code = data.code;
			socket.emit 'loggedin', App.codes[code]

		socket.on 'skip', (songId)->
			if !code? || !App.codes? || !App.codes[code]? || !App.codes[code].canSkip
				return App.sendError socket, 'You can\'t do that!'
			App.play()

		socket.on 'remove', (songId)->
			if !code? || !App.codes? || !App.codes[code]? || !App.codes[code].canDelete
				return App.sendError socket, 'You can\'t do that!'
			for i in [0...App.playlist.length]
				if App.playlist[i].id == songId
					App.playlist.splice(i,1);
					break;
			App.io.emit 'playlist', App.playlist


		socket.on 'vote', (data) ->
			if !code?
				return App.sendError socket, 'Invalid code'
			if !data.id?
				return App.sendError socket, 'Missing id'
			if !data.score?
				return App.sendError socket, 'Missing score'
			if !App.songs? || !App.songs[data.id]?
				return App.sendError socket, 'Unknown song'
			
			score = if parseInt(data.score) > 0 then 1 else -1
			console.log 'Score', score

			for i in [0...App.playlist.length]
				if App.playlist[i].id == data.id
					console.log 'Found it', data.id, App.playlist[i]
					score = 1*score + 1*App.playlist[i].count
					console.log 'new score', score
					App.playlist.splice i, 1
					break;

			song = App.songs[data.id]
			song.count = score;
			song.id = data.id
			App.playlist.push song

			App.playlist.sort (a,b)->
				if a.count < b.count
					return 1
				if a.count > b.count
					return -1
				return 0;

			App.io.emit 'playlist', App.playlist
			if !App.isPlaying
				App.play();

		socket.on 'disconnect', ()->
			

	
	sendTo:(userId, message)->
		if App.subscriptions? && App.subscriptions[userId]? && App.subscriptions[userId].length?
			for i in[0...App.subscriptions[userId].length]
				console.log 'sending to userid '+userId
				App.subscriptions[userId][i].emit 'notification', message;

	
	sendError:(socket, text)->
		if socket? && socket.emit?
			socket.emit('problem', text);


App.init(require('./config.json'));

