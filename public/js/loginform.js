// JavaScript Document
$(function() {
	  //debugger;
    $('input[name=authenticity_token]').val($('meta[name=csrf-token]').attr('content'))
});
