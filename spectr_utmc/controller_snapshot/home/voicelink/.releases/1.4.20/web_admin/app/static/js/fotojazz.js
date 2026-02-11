fotojazz.operations = function() {
    function process_start(process_css_name,
                           process_class_name,
                           extra_args) {

        // ...

        $('#operation-' + process_css_name).click(function() {
            // ...

            $.getJSON(SCRIPT_ROOT + '/process/start/' +
                      process_class_name + '/',
            args,
            function(data) {
                $('#operation-' + process_css_name).attr('disabled',
                                                         'disabled');
                $('#operation-' + process_css_name + '-progress')
                .progressbar('option', 'disabled', false);
                $('#operation-' + process_css_name + '-progress')
                .progressbar('option', 'value', data.percent);
                setTimeout(function() {
                    process_progress(process_css_name,
                                     process_class_name,
                                     data.key);
                }, 100);
            });
            return false;
        });
    }
    
    function process_progress(process_css_name,
                              process_class_name,
                              key) {
        $.getJSON(SCRIPT_ROOT + '/process/progress/' +
                  process_class_name + '/',
        {
            'key': key
        }, function(data) {
            $('#operation-' + process_css_name + '-progress')
            .progressbar('option', 'value', data.percent);
            if (!data.done) {
                setTimeout(function() {
                    process_progress(process_css_name,
                                     process_class_name,
                                     data.key);
                }, 100);
            }
            else {
                $('#operation-' + process_css_name)
                .removeAttr('disabled');
                $('#operation-' + process_css_name + '-progress')
                .progressbar('option', 'value', 0);
                $('#operation-' + process_css_name + '-progress')
                .progressbar('option', 'disabled', true);

                // ...
            }
        });
    }
    
    // ...
    
    return {
        init: function() {
            $('.operation-progress').progressbar({'disabled': true});
            
            // ...
            
            process_start('dummy', 'FotoJazzProcess');

            // ...
        }
    }
}();


$(function() {
    fotojazz.operations.init();
});