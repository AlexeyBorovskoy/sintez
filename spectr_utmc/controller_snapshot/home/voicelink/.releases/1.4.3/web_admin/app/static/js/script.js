var currentStep = 1, editStatus = false;
jQuery(function($) {
    $('select, input[type="radio"], input[type="checkbox"]').styler({selectSearch:false});

    $('.radio-input').click(function(e){
        $('#SexInput').val($(this).attr('data-value'));
        $('.radio-input').removeClass('active');
        $(this).addClass('active');
    });

    $('#NextStep').click(function(e) {
        if(currentStep == 3) return;
        e.preventDefault();
        currentStep++;
        progress(currentStep);
    });
    $('.steps').click(function(e) {
        var step = $(this).attr('data-step');
        if(!$(this).hasClass('active')) return;
        currentStep = step;
        progress(step);
    });
    
    // Редактирование настроек
    $('#EditLink').click(function(e){
        e.preventDefault();
        if(editStatus) cancelEditSettings();
        else editSettings();
    });

    function progress(step) {
        var progressSteps = $('.steps');
        if(step == 3) setProgress(100);
        else if(step == 2) setProgress(70);
        else setProgress(30);
        $('#userDataForm fieldset').addClass('hide');
        $('#userDataForm fieldset[data-step='+step+']').removeClass('hide');
        if(step > 2) $('#NextStep').val('Завешить');
        else $('#NextStep').val('Дальше');
        step -= 1;
        progressSteps.removeClass('current').removeClass('active');
        for(var i = 0; i < 3; i++) {
            if(i == step) {
                progressSteps.eq(i).addClass('current');
                return;
            } else {
                progressSteps.eq(i).addClass('active');
            }
        }
    }
    function setProgress(percent){
        console.log(percent);
        $('.progress').animate({width: percent+'%'}, 'fast');
    }
    
    function editSettings(){
        $('#EditLink').text('Отмена');
        $('#OKButton').removeClass('button2').addClass('button').val('Сохранить');
        // Подсталяем поля ввода для телефона и email
        $('.js_sett_input').show().queue(function(){
            var input = $(this).find('input'),
                text = $(this).prev('span').text();
            input.val(text);
        });
        $('.waight-data-input .subdata').eq(0).css({top:'9px',left:'8px'});
        $('.waight-data-input .subdata').eq(1).css({top:'9px',left:'4px'});
        $('.waight-data-input .subdata').eq(2).css({top:'9px'});
        $('.waight-data-info li.center').css('height','70px');
        $('.connection-data').css('margin-top', '30px');
        $('.info-row').css({height:'34px'});
        
        editStatus = true;
    }
    function cancelEditSettings(){
        $('#EditLink').text('Редактировать');
        $('#OKButton').removeClass('button').addClass('button2').val('Ok');
        $('.js_sett_input').hide();
        $('.waight-data-input .subdata').css({top:0,left:0});
        $('.waight-data-info li.center').css('height','50px');
        $('.connection-data').css('margin-top', '50px');
        $('.info-row').css({height:'auto'});
        
        editStatus = false;
    }
});