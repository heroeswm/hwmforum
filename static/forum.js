function answer_to(nick) {
	var postform = document.getElementById('postform');
	if (postform) postform.msg.value += 'для '+nick+':\n';
	return false;
}

function getSelectedText() {
	if (window.getSelection) {
		return window.getSelection();
	} else if (document.selection) {
		return document.selection.createRange().text;
	}
	return '';
}

function quote_text() {
	var postform = document.getElementById('postform');
	var selection = getSelectedText().toString();
	selection = selection.replace(/^\\s+|\\s+$/g, '');
	if (postform) postform.msg.value += '[quote]'+selection+'[/quote]\n';
	return false;
}

function hashchanged() {
	if (typeof hashchanged.oldhash == 'undefined') {
		hashchanged.oldhash = '';
	}

	var oldhash = hashchanged.oldhash;
	var hash = location.hash.replace('#', '');
	if (oldhash) {
		$('a[name="'+oldhash+'"]').removeClass('msgfocused');
	}
	if (hash) {
		$('a[name="'+hash+'"]').addClass('msgfocused');
	}
	hashchanged.oldhash = hash;
}

function msgvote_click(evt)
{
	if (evt.target.nodeName != 'A') {
//		var div = $(evt.target).html('привет :)');
		return false;
	}
	var div = $(evt.target).parent();
	div.html('-');
	div.css('font-family', 'monospace');

	var state = 0;
	var interval = setInterval(function() {
		state++;
		var array = ['-', '\\', '|', '/'];
		div.html(array[state%4]);
	}, 300);

	$.get(evt.target.href+'&js=1', '', function(data) {
		div.css('font-family', '');
		clearInterval(interval);
		div.html(data);
	});
	return false;
}

function jsdel_click(evt)
{
	var res = '<form method="post" action="forum_change.pl">';
	res += '<input type="hidden" name="action" value="delmsg"/>';
	res += '<input type="hidden" name="page" value="'+window.hwmforum.page+'"/>';
	res += '<input type="hidden" name="id" value="'+window.hwmforum.tid+'"/>';
	res += '<input type="hidden" name="msgid" value="'+$(evt.target).attr('msgid')+'"/>';
	res += '<input type="hidden" name="chk" value="'+window.hwmforum.token+'"/>';
	res += 'Причина: <input type="text" name="reason"/> <input maxlength="254" type="submit" value="Удалить сообщение"/>';
	res += '</form>';
	$(evt.target).parent().html(res);
	return false;
}

function jsban_click(evt)
{
	var res = '<form method="post" action="forum_change.pl">';
	res += '<input type="hidden" name="action" value="banmsg"/>';
	res += '<input type="hidden" name="page" value="'+window.hwmforum.page+'"/>';
	res += '<input type="hidden" name="id" value="'+window.hwmforum.tid+'"/>';
	res += '<input type="hidden" name="msgid" value="'+$(evt.target).attr('msgid')+'"/>';
	res += '<input type="hidden" name="chk" value="'+window.hwmforum.token+'"/>';
	//res += 'Бан: <select name="type"><option value="1">предупреждение</option><option value="2">на тему</option><option value="3">на подфорум</option><option value="4">на категорию</option><option value="5">глобальный</option></select> ';
	res += 'Бан на <input type="text" name="time" size=5/> часов, ';
	res += 'причина: <input type="text" name="reason"/> <input maxlength="254" type="submit" value="Наказать игрока"/>';
	res += '</form>';
	$(evt.target).parent().html(res);
	return false;
}

function addpanel_closed()
{
	$('<a class="icon" href="#"><span class="icon ">&laquo;</span></a>').appendTo($('#edit_panel')).click(function() {
		$('#edit_panel').html('');
		change_settings('bbpanel', 'on');
		addpanel_opened();
		return false;
	});
}

function addpanel_opened()
{
	function add_code(code)
	{
		return function() {
			var msg = $('#msg')[0];
			msg.value = 
				msg.value.substring(0, msg.selectionStart) + '[' + code + ']' +
				msg.value.substring(msg.selectionStart, msg.selectionEnd) + '[/' + code + ']' +
				msg.value.substring(msg.selectionEnd);
			return false;
		}
	}

	$('<a class="icon" href="#"><span class="icon bold">B</span></a>').appendTo($('#edit_panel')).click(add_code('b'));
	$('<a class="icon" href="#"><span class="icon italic">I</span></a>').appendTo($('#edit_panel')).click(add_code('i'));
	$('<a class="icon" href="#"><span class="icon normal">N</span></a>').appendTo($('#edit_panel')).click(add_code('n'));
	$('<a class="icon" href="#"><span class="icon strike">S</span></a>').appendTo($('#edit_panel')).click(add_code('strike'));
	$('<a class="icon" href="#"><span class="icon code">M</span></a>').appendTo($('#edit_panel')).click(add_code('code'));
	$('<a class="icon" href="#"><span class="icon quote">Q</span></a>').appendTo($('#edit_panel')).click(function() {
		if (getSelectedText() != '') {
			quote_text();
		} else {
			(add_code('quote'))();
		}
		return false;
	});
	$('<a class="icon" href="#"><span class="icon ">&raquo;</span></a>').appendTo($('#edit_panel')).click(function() {
		$('#edit_panel').html('');
		change_settings('bbpanel', 'off');
		addpanel_closed();
		return false;
	});
}

function change_settings(key, value)
{
	$.get('settings.pl?js=1&k='+escape(key)+'&v='+escape(value)+'&chk='+window.hwmforum.token+'&tid='+window.hwmforum.tid);
}

function vote_variant_add()
{
	$('<tr><td class="pollvar"><input type="text" name="choice'+(Number($('#answers_text').attr('rowspan'))+1)+'" maxlength=120/></td></tr>').insertAfter($('.pollvar').last().parent());
	$('#answers_text').attr('rowspan', Number($('#answers_text').attr('rowspan'))+1);
	return false;
}

$(document).ready(function() {
	var oldsubmit;
	function submitfunc() {
		oldsubmit = $('#btn').attr('value');
		$('#btn').attr('value', "Сообщение отправляется...");
		$('#btn').attr("disabled", true);
		setTimeout(function() {
			$('#btn').attr('value', oldsubmit);
			$('#btn').attr("disabled", false);
		}, 4000);
		return true;
	};
	var postform = document.getElementById('postform');
	if (postform) {
		postform.msg.onkeydown = function(e) {
			e = e || event;
			if (e.keyCode == 13 && e.ctrlKey) {
				submitfunc();
				postform.submit();
			}
		};
		$(postform).submit(submitfunc);
	}
	
	if ("onhashchange" in window) {
		window.onhashchange = hashchanged;
	}
	hashchanged();

	$('.msgvote').click(msgvote_click);
	$('.jsdel').click(jsdel_click);
	$('.jsban').click(jsban_click);
	if (window.hwmforum !== undefined && window.hwmforum.bbpanel == 'on') {
		addpanel_opened();
	} else {
		addpanel_closed();
	}
	$('#msg').elastic();
	$('#newtopic_add').click(vote_variant_add);
	
	(function display_admin() {
		var grps = $('.fgrps');
		if (grps.length > 1) {
			$(grps[1]).click(function() {
				if ($('#admin_eegg').length > 0) return;
				var tr = $(this);
				var off = tr.offset();
				var img = $('<img src="static/admin.gif" id="admin_eegg" width=67 height=100 />');
				img.hide();
				img.bind('load', function () { $(this).fadeIn(1000); });
				$('body').append(img);
				img.css({
					position: 'absolute',
					left: off.left + tr.width() - 150,
					'top': off.top-75,
				});
			})
		}
	})();
});

/**
*	@name							Elastic
*	@descripton						Elastic is jQuery plugin that grow and shrink your textareas automatically
*	@version						1.6.10
*	@requires						jQuery 1.2.6+
*
*	@author							Jan Jarfalk
*	@author-email					jan.jarfalk@unwrongest.com
*	@author-website					http://www.unwrongest.com
*
*	@licence						MIT License - http://www.opensource.org/licenses/mit-license.php
*/
/*
(function(jQuery){ 
	jQuery.fn.extend({  
		elastic: function() {
		
			//	We will create a div clone of the textarea
			//	by copying these attributes from the textarea to the div.
			var mimics = [
				'paddingTop',
				'paddingRight',
				'paddingBottom',
				'paddingLeft',
				'fontSize',
				'lineHeight',
				'fontFamily',
				'width',
				'fontWeight',
				'border-top-width',
				'border-right-width',
				'border-bottom-width',
				'border-left-width',
				'borderTopStyle',
				'borderTopColor',
				'borderRightStyle',
				'borderRightColor',
				'borderBottomStyle',
				'borderBottomColor',
				'borderLeftStyle',
				'borderLeftColor'
				];
			
			return this.each( function() {
				
				// Elastic only works on textareas
				if ( this.type !== 'textarea' ) {
					return false;
				}
					
			var $textarea	= jQuery(this),
				$twin		= jQuery('<div />').css({'position': 'absolute','display':'none','word-wrap':'break-word'}),
				lineHeight	= parseInt($textarea.css('line-height'),10) || parseInt($textarea.css('font-size'),'10'),
				minheight	= parseInt($textarea.css('height'),10) || lineHeight*3,
				maxheight	= parseInt($textarea.css('max-height'),10) || Number.MAX_VALUE,
				goalheight	= 0;
				
				// Opera returns max-height of -1 if not set
				if (maxheight < 0) { maxheight = Number.MAX_VALUE; }
					
				// Append the twin to the DOM
				// We are going to meassure the height of this, not the textarea.
				$twin.appendTo($textarea.parent());
				
				// Copy the essential styles (mimics) from the textarea to the twin
				var i = mimics.length;
				while(i--){
					$twin.css(mimics[i].toString(),$textarea.css(mimics[i].toString()));
				}
				
				// Updates the width of the twin. (solution for textareas with widths in percent)
				function setTwinWidth(){
					curatedWidth = Math.floor(parseInt($textarea.width(),10));
					if($twin.width() !== curatedWidth){
						$twin.css({'width': curatedWidth + 'px'});
						
						// Update height of textarea
						update(true);
					}
				}
				
				// Sets a given height and overflow state on the textarea
				function setHeightAndOverflow(height, overflow){
				
					var curratedHeight = Math.floor(parseInt(height,10));
					if($textarea.height() !== curratedHeight){
						$textarea.css({'height': curratedHeight + 'px','overflow':overflow});
						
						// Fire the custom event resize
						$textarea.trigger('resize');
						
					}
				}
				
				// This function will update the height of the textarea if necessary 
				function update(forced) {
					
					// Get curated content from the textarea.
					var textareaContent = $textarea.val().replace(/&/g,'&amp;').replace(/ {2}/g, '&nbsp;').replace(/<|>/g, '&gt;').replace(/\n/g, '<br />');
					
					// Compare curated content with curated twin.
					var twinContent = $twin.html().replace(/<br>/ig,'<br />');
					
					if(forced || textareaContent+'&nbsp;' !== twinContent){
					
						// Add an extra white space so new rows are added when you are at the end of a row.
						$twin.html(textareaContent+'&nbsp;');
						
						// Change textarea height if twin plus the height of one line differs more than 3 pixel from textarea height
						if(Math.abs($twin.height() + lineHeight - $textarea.height()) > 3){
							
							var goalheight = $twin.height()+lineHeight;
							if(goalheight >= maxheight) {
								setHeightAndOverflow(maxheight,'auto');
							} else if(goalheight <= minheight) {
								setHeightAndOverflow(minheight,'hidden');
							} else {
								setHeightAndOverflow(goalheight,'hidden');
							}
							
						}
						
					}
					
				}
				
				// Hide scrollbars
				$textarea.css({'overflow':'hidden'});
				
				// Update textarea size on keyup, change, cut and paste
				$textarea.bind('keyup change cut paste', function(){
					update(); 
				});
				
				// Update width of twin if browser or textarea is resized (solution for textareas with widths in percent)
				$(window).bind('resize', setTwinWidth);
				$textarea.bind('resize', setTwinWidth);
				$textarea.bind('update', update);
				
				// Compact textarea on blur
				$textarea.bind('blur',function(){
					if($twin.height() < maxheight){
						if($twin.height() > minheight) {
							$textarea.height($twin.height());
						} else {
							$textarea.height(minheight);
						}
					}
				});
				
				// And this line is to catch the browser paste event
				$textarea.bind('input paste',function(e){ setTimeout( update, 250); });				
				
				// Run update once when elastic is initialized
				update();
				
			});
			
        } 
    }); 
})(jQuery);*/
