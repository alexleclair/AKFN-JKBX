App = 
	config:
		endpoint:'/'
		server:
			requireLogin:false
			allowAnonymous:true
		user:{
			canDelete:false,
			canRevote:false,
			canSkip:false,
			voteLimit:false
		}

	socket:null
	code:null
	songs:{}
	init:->
		$.getScript App.config.endpoint+'socket.io/socket.io.js', ->
			App.onLoad();
			$('.page.loading p').removeClass('hide').hide().filter('.loadjs').show();

			$('a.search-icon').on 'click', (e)->
				e.preventDefault();
				App.gotoPage 'search'
				return false;

			$('a.list-icon').on 'click', (e)->
				e.preventDefault();
				App.gotoPage 'list'
				return false;

			$('a.random-icon').on 'click', (e)->
				e.preventDefault();
				_artist = '';
				_artists = []
				for key of App.songs
					if App.songs[key].artist? && App.songs[key].artist.length > 0
						_artists.push App.songs[key].artist[Math.floor(Math.random()*App.songs[key].artist.length)]
				_artist = _artists[Math.floor(Math.random()*_artists.length)];
				$('.tt-input.search').focus().typeahead('val', _artist).typeahead('open')
				return false;

			$('a.back-icon').on 'click', (e)->
				e.preventDefault();
				App.gotoPage 'playlist'
				return false;

	onLoad:()->
		App.socket = io(App.config.endpoint);
		$('.page.loading p').removeClass('hide').hide().filter('.connecting').show();

		App.socket.on 'connect', ->
			$('.page.loading p').fadeOut('fast')
			$('.page.loading p.fetching').fadeIn('fast')

		$("input.search").typeahead 
			minLength:2,
			highlight:false
		,
			source:(query,process)->
				clearTimeout App._searchTimer
				App._searchTimer = setTimeout ()->
					App.search query, process
					ga('send','pageview', '/search/'+encodeURIComponent(query))
				, 500
			,
			displayKey: 'title'
			templates:
				empty:[
					'<strong>Oops. Y\'a rien ici!</strong>'
				].join("\n"),
				suggestion:Handlebars.compile('<p class="result"><strong>{{title}}</strong><br /> {{artist}} <br/> <em>{{album}}</em></p>')

		$('input.search').on 'typeahead:selected', (e, suggestion, dataset) ->
			App.vote suggestion.id
			$('.tt-input.search').typeahead('val', '').blur()
			App.gotoPage 'playlist';

			return false;

		


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

		App.socket.on 'addSong', (song,id)->
			App.songs[id] = song;

		App.socket.on 'removeSong', (songId)->
			if App.songs[songId]?
				delete App.songs[songId]

		App.socket.on 'songs', (data)->
			App.songs = data
			$('.page.loading p.fetching').fadeOut 'slow', ->
				$('.page.loading p.ready').hide().fadeIn 'slow', ->
					setTimeout ->
						if App.config.server.requireLogin || !App.config.server.allowAnonymous || (location.search+'').indexOf('login') >= 0
							$('body').addClass('require-login')
							App.gotoPage('login');
						else
							App.gotoPage('playlist')
					, 700

		App.socket.on 'loggedin', (data)->
			App.config.user = data
			App.gotoPage('playlist');

	setPlaylist:(data)->
		if !data?
			data = App.playlist;
		$ul = $('.page.playlist ul');
		$ul.html('');
		for i in [0...data.length]
			song = data[i]
			$li = $('<li/>').html(App.getSongHtml(song)).attr('data-id', song.id)

			if App.config.user.canRevote? && App.config.user.canRevote
				$a = $('<a />').html('<span class="glyphicon glyphicon-thumbs-up"></span>').addClass('up');
				$li.append($a)
				$a = $('<a />').html('<span class="glyphicon glyphicon-thumbs-down"></span>').addClass('down');
				$li.append($a);

			if App.config.user.canDelete? && App.config.user.canDelete
				$a = $('<a />').html('<span class="glyphicon glyphicon-remove"></span>').addClass('remove');
				$li.append($a);

			# $li.addClass('list-group-item')

			$li.find('a.up, a.down').on 'click', (e)->
				e.preventDefault();
				App.vote $(this).parent().attr('data-id'), if $(this).is('.up') then 1 else -1
				return false;


			if song.isCurrent? && song.isCurrent
				$li.addClass('disabled');
				$li.find('a').remove();
			$ul.append $li;
		if $ul.find('li.disabled').length == 0 && App.currentSong?
			song = App.currentSong
			html = App.getSongHtml(song);

			$li = $('<li/>').html(html).attr('data-id', song.id).addClass('current')
			if App.config.user.canSkip? && App.config.user.canSkip
				$a = $('<a />').html('<span class="glyphicon glyphicon-remove"></span>').addClass('skip');
				$li.append($a);
			$ul.prepend($li);

		$ul.find('a.skip, a.remove').on 'click', (e)->
				e.preventDefault();
				id = $(this).parent().attr('data-id');
				if $(this).is('.remove')
					App.socket.emit 'remove', id
				if $(this).is('.skip')
					App.socket.emit 'skip', id
				return false;

		App.playlist = data;

	login:(code)->
		App.code = code
		App.socket.emit 'login', {code}
		ga('send','pageview', '/login/'+encodeURIComponent(code))


	getSongHtml:(song)->
		html = '<div class="info">';
		if song.artist? && song.artist.length > 0
			html += '<span class="artist">' + $('<div />').text(song.artist.join(' & ')).html() + '</span>';

		if song.artist? && song.artist.length? && song.album? && song.album.length > 0
			html += ' &mdash; ';

		if song.album?
			html += '<span class="album">' + $('<div />').text(song.album).html() + '</span>'

		html += '</div>'

		info = html;

		html = '';

		html += '<span class="title">' + $('<div />').text(song.title).html() + '</span>'

		if song != App.currentSong
			html += info;
		else
			html = info+html

	gotoPage:(page)->
		ga('send','pageview', '/virtual/'+encodeURIComponent(page))
		$('.page').not('.'+page).fadeOut 'fast', ->
			if page == 'list'
				_songs = []
				cache = {}
				for key of App.songs
					_artist = App.songs[key].artist.join(' & ') + ''
					if _artist? && _artist != '' && !cache[_artist]?
						_songs.push _artist
						cache[_artist] = true

				_songs.sort (a,b)->
					if a.toUpperCase() < b.toUpperCase()
						return -1
						
					if a.toUpperCase() > b.toUpperCase()
						return 1

					return 0;
				$ul = $('.page.list ul:first')
				$ul.html('');
				for i in [0..._songs.length]
					$li = $('<li />').text(_songs[i]);
					$li.on 'click', (e)->
						App.gotoPage 'search'
						$('.tt-input.search').focus().typeahead('val', $(this).text()).typeahead('open')
					$ul.append($li)
			$('.page.'+page).fadeIn 'fast', ->
				if page == 'search'
					$('.tt-input.search').focus();
				if page == 'playlist'
					App.setPlaylist()
					# $search = $('input.search.tt-input');
					# $search.focus()
					# clearInterval App.demoInterval
					# App.demoInterval = setInterval ()->
					# 	val = $search.val();
					# 	text = $search.attr('placeholder');
					# 	if val? && val.length == text.length
					# 		clearInterval App.demoInterval;
					# 		App.demoInterval = setInterval ()->
					# 			$search.val('')
					# 			clearInterval App.demoInterval
					# 		, 1000
					# 		return;
					# 	val = val + '' + text.substr(val.length,1);
					# 	$search.val(val);

					# , 80

	vote:(song, score=1)->
		console.log 'Vote', song, score
		App.socket.emit 'vote', {id:song, score:score}
		ga('send','pageview', '/vote/'+score+'/'+encodeURIComponent(song))

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
						rank += 30
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

		x = _songs.splice(0,60);
		# x.reverse();
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
	if false && ((window.location+'').indexOf('ngrok.com') >= 0 || (window.location+'').indexOf('jukebox.zloche.net') >= 0)
		App.config.endpoint = 'http://dc3cd24.ngrok.com:80/';
	else if (window.location+'').indexOf('/localhost:9000') >= 0
		App.config.endpoint = 'http://localhost:8090/'
	App.init();
	code = Cookie.read 'code'
	if code? && code != ''
		$('.page.login .jumbotron input').val(code);

	$('.page.login .jumbotron a.btn').on 'click', (e)->
		e.preventDefault();
		App.login $(this).parents('.jumbotron').find('input').val()

window.App = App;