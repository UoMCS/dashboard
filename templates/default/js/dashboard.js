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


function delete_repos()
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "nukecheck"),
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
                                         $('poptitle').set('text', respElems[0].get('text'));
                                         $('popbody').empty().grab(respElems[1]);
                                         popbox.setButtons([{title: respElems[2].get('text'), color: 'red', event: function() { do_delete_repos() } },
                                                            {title: respElems[3].get('text'), color: 'blue', event: function() { popbox.close(); }}]);
                                         popbox.open();
                                     }
                                     $('workspinner').fade('out');
                                     enable_repos_controls();
                                     updatelock = false;
                                 }
                               });
    req.post();

    return false;
}


function do_delete_repos()
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request({ url: api_request_path("dashboard", "donuke"),
                            method: 'post',
                            onRequest: function() {
                                $('workspinner').fade('in');
                                disable_repos_controls();
                            },
                            onSuccess: function(respText, respXML) {
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    popbox.close();
                                    errbox.open();
                                } else {
                                    var res = respXML.getElementsByTagName("return")[0];
                                    var rup = res.getAttribute("url");

                                    if(rup)
                                        location.href = rup;
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
