App = 
	config:
		endpoint:'http://localhost:8090/'
		server:
			requireLogin:false
			allowAnonymous:true

	socket:null
	code:null
	songs:{}
	init:->
		$.getScript App.config.endpoint+'socket.io/socket.io.js', ->
			App.onLoad();
			$('.page.loading p').removeClass('hide').hide().filter('.loadjs').show();

	onLoad:()->
		App.socket = io(App.config.endpoint);
		$('.page.loading p').removeClass('hide').hide().filter('.connecting').show();

		App.socket.on 'connect', ->
			$('.page.loading p').fadeOut('fast')
			$('.page.loading p.fetching').fadeIn('fast')

		$(".search").typeahead 
			minLength:2,
			highlight:false
		,
			source:(query,process)->
				clearTimeout App._searchTimer
				App._searchTimer = setTimeout ()->
					App.search query, process
				, 500
			,
			displayKey: 'title'
			templates:
				empty:[
					'<strong>Oops. Y\'a rien ici!</strong>'
				].join("\n"),
				suggestion:Handlebars.compile('<p class="result"><strong>{{title}}</strong><br /> {{artist}} <br/> <em>{{album}}</em></p>')

		$('.search').on 'typeahead:selected', (e, suggestion, dataset) ->
			App.vote suggestion.id

			return false;


		App.socket.on 'playing', (song)->
			console.log 'playing', song

		App.socket.on 'config', (config)->
			App.config.server = config
			console.log 'Got config', config

		App.socket.on 'playlist', (data)->
			App.setPlaylist(data)

		App.socket.on 'playing', (song)->
			App.currentSong = song
			App.setPlaylist()

		App.socket.on 'problem', (data)->
			alert data

		App.socket.on 'songs', (data)->
			App.songs = data
			$('.page.loading p.fetching').fadeOut 'slow', ->
				$('.page.loading p.ready').hide().fadeIn 'slow', ->
					setTimeout ->
						if App.config.server.requireLogin || !App.config.server.allowAnonymous 
							App.gotoPage('login');
						else
							App.gotoPage('playlist')
					, 700

		App.socket.on 'loggedin', (data)->
			App.gotoPage('playlist');

	setPlaylist:(data)->
		if !data?
			data = App.playlist;
		$ul = $('.page.playlist ul');
		$ul.html('');
		for i in [0...data.length]
			song = data[i]
			$li = $('<li/>').text(song.artist.join(' & ') + ' - ' + song.title).attr('data-id', song.id)
			$a = $('<a />').html('<span class="glyphicon glyphicon-thumbs-up"></span>').addClass('up');
			$li.append($a)
			$a = $('<a />').html('<span class="glyphicon glyphicon-thumbs-down"></span>').addClass('down');
			$li.append($a).addClass('list-group-item')

			$li.find('a').on 'click', (e)->
				e.preventDefault();
				App.vote $(this).parent().attr('data-id'), if $(this).is('.up') then 1 else -1
				return false;
			if song.isCurrent? && song.isCurrent
				$li.addClass('disabled');
				$li.find('a').remove();
			$ul.append $li;
		if $ul.find('li.disabled').length == 0 && App.currentSong?
			song = App.currentSong
			$li = $('<li/>').text(song.artist.join(' & ') + ' - ' + song.title).attr('data-id', song.id).addClass('disabled list-group-item')
			$ul.prepend($li);
		App.playlist = data;

	login:(code)->
		App.code = code
		App.socket.emit 'login', {code}

	gotoPage:(page)->
		$('.page').not('.'+page).slideUp 'fast', ->
			$('.page.'+page).slideDown('fast');

	vote:(song, score=1)->
		console.log 'Vote', song, score
		App.socket.emit 'vote', {id:song, score:score}

	search:(query, process)->

		query = query.split(' ');
		songs = {}
		for i in [0...query.length]
			if query[i] == ''
				continue;
			word = query[i].toLowerCase()

			for key of App.songs
				song = App.songs[key]
				rank = 0;
				tests = [song.title, song.album]
				for j in [0...song.artist.length]
					tests.push song.artist[j];

				for j in [0...tests.length]
					if song.title.toLowerCase().split(' ').indexOf(word) >= 0
						rank += 15
					if tests[j].toLowerCase().split(' ').join('').indexOf(word) >= 0
						rank += 8
					if tests[j].toLowerCase().replace(/[aeiou]/ig,'').split(' ').indexOf(word.replace(/[aeiou]/ig,'')) >= 0
						rank += 3
					if tests[j].toLowerCase().replace(/[aeiou]/ig,'').split(' ').join('').indexOf(word.replace(/[aeiou]/ig,'')) >= 0
						rank += 1
				
				if rank == 0
					continue;
				
				if !songs[key]?
					_song = 
						id:key
						title:song.title
						artist: if song.artist? && song.artist.length? song.artist.join(' & ') else song.artist
						album: song.album
						rank:rank
					songs[key] = _song;
				else
					songs[key].rank = (songs[key].rank + rank)*1.25

		_songs = [];
		for key of songs
			_songs.push songs[key]
		_songs.sort (a,b)->
			if a.rank > b.rank
				return -1;
			if a.rank < b.rank
				return 1;
			return 0

		x = _songs.splice(0,15);
		__songs = []
		for i in [0...x.length]
			__songs.push x[i].title+' - '+x[i].artist
		process(x);
		return __songs


Cookie = 
	create:(name,value,days)->
		expires = ""
		if days?
			date = new Date()
			date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
			expires = "; expires=" + date.toGMTString();
		document.cookie = name + "=" + escape(value) + expires + "; path=/";
	read:(c_name)->
		if document.cookie.length > 0
			c_start = document.cookie.indexOf(c_name + "=");
		if c_start != -1
			c_start = c_start + c_name.length + 1;
			c_end = document.cookie.indexOf(";", c_start);
			if c_end == -1
				c_end = document.cookie.length;
			return unescape(document.cookie.substring(c_start, c_end));
window.Cookie = Cookie
$ ->
	if (window.location+'').indexOf('ngrok.com') >= 0
		App.config.endpoint = 'http://dc3cd24.ngrok.com:80/';
	else if (window.location+'').indexOf('/localhost') < 0
		App.config.endpoint = '/'
	App.init();
	code = Cookie.read 'code'
	if code? && code != ''
		$('.page.login .jumbotron input').val(code);

	$('.page.login .jumbotron a.btn').on 'click', (e)->
		e.preventDefault();
		App.login $(this).parents('.jumbotron').find('input').val()

window.App = App;