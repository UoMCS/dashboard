var updatelock = false;

function enable_repos_controls()
{
    if($('pullrepos'))
        $('pullrepos').addEvent('click', function() { update_repos(); }).removeClass('disabled');

    if($('nukerepos'))
        $('nukerepos').addEvent('click', function() { delete_repos(); }).removeClass('disabled');

    if($('newrepos'))
        $('newrepos').addEvent('click', function() { change_repos(); }).removeClass('disabled');
}


function disable_repos_controls()
{
    $('pullrepos').removeEvents('click').addClass('disabled');
    $('nukerepos').removeEvents('click').addClass('disabled');
    $('newrepos').removeEvents('click').addClass('disabled');
}


function update_repos()
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "pullrepo"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspinner').fade('in');
                                     disable_repos_controls();
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);

                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                     // No error, post was edited, the element provided should
                                     // be the new <li>...
                                     } else {
                                         var tmp = new Element('div').adopt(respTree);
                                         tmp = tmp.getChildren()[0];
                                         tmp.setStyle("display", "none");

                                         if($('notebox')) $('notebox').destroy();
                                         $('infobox').adopt(tmp);
                                         tmp.reveal();
                                         setTimeout(function() { $('notebox').dissolve() }, 8000);
                                     }

                                     $('workspinner').fade('out');
                                     enable_repos_controls();
                                     updatelock = false;
                                 }
                               });
    req.post();

    return false;
}

window.addEvent('domready', function()
{
    if($('web-repos'))
        new OverText('web-repos');

    if($('notebox'))
        setTimeout(function() { $('notebox').dissolve() }, 8000);

    enable_repos_controls();
});
