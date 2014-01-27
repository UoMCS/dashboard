var updatelock = false;

/** Disable the submission button for a form. This is an attempt to
 *  prevent, or at least reduce the likelihood, of repeat submissions.
 */
function form_protect(submit, spinner)
{
    if(!spinner) spinner = 'workspinner';

    $(submit).set('disabled', true);
    $(submit).addClass('disabled');
    $(spinner).fade('in');

    return true;
}


/** Enable the buttons controlling features of the repository.
 *
 */
function enable_repos_controls(id)
{
    if($('updatebtn-'+id))
        $('updatebtn-'+id).addEvent('click', function() { show_token(); }).removeClass('disabled');

    if($('remotebtn-'+id))
        $('remotebtn-'+id).addEvent('click', function() { update_repos(); }).removeClass('disabled');

    if($('deletebtn-'+id))
        $('deletebtn-'+id).addEvent('click', function() { delete_repos(); }).removeClass('disabled');

    if($('changebtn-'+id))
        $('changebtn-'+id).addEvent('click', function() { change_repos(); }).removeClass('disabled');
}


/** Disable the buttons controlling features of the repository.
 *
 */
function disable_repos_controls(id)
{
    $('updatebtn-'+id).removeEvents('click').addClass('disabled');
    $('deletebtn-'+id).removeEvents('click').addClass('disabled');
    $('deletebtn-'+id).removeEvents('click').addClass('disabled');
    $('changebtn-'+id).removeEvents('click').addClass('disabled');
}


/** Enable the buttons controlling features of the database.
 *
 */
function enable_database_controls()
{
    if($('newdbpass'))
        $('newdbpass').addEvent('click', function() { change_password(); }).removeClass('disabled');

    if($('nukedb'))
        $('nukedb').addEvent('click', function() { delete_database(); }).removeClass('disabled');
}


/** Disable the buttons controlling features of the database.
 *
 */
function disable_database_controls()
{
    $('newdbpass').removeEvents('click').addClass('disabled');
    $('nukedb').removeEvents('click').addClass('disabled');
}


function show_token(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "gettoken"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspinner').fade('in');
                                     disable_repos_controls(pathid);
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);

                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                     // No error, post was edited, the element provided should
                                     // be the new <li>...
                                     } else {
                                         $('poptitle').set('text', respTree[0].get('text'));
                                         $('popbody').empty().grab(respTree[2]);
                                         popbox.setButtons([{title: respTree[3].get('text'), color: 'blue', event: function() { popbox.close(); }}]);
                                         popbox.open();
                                     }
                                     $('workspinner').fade('out');
                                     enable_repos_controls(pathid);
                                     updatelock = false;
                                 }
                               });
    req.send({id: pathid});

    return false;
}


function update_repos(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "pullrepo"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspinner').fade('in');
                                     disable_repos_controls(pathid);
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
                                     enable_repos_controls(pathid);
                                     updatelock = false;
                                 }
                               });
    req.send({id: pathid});

    return false;
}


function delete_repos(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "webnukecheck"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspinner').fade('in');
                                     disable_repos_controls(pathid);
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
                                         popbox.setButtons([{title: respElems[2].get('text'), color: 'red', event: function() { do_delete_repos(pathid) } },
                                                            {title: respElems[3].get('text'), color: 'blue', event: function() { popbox.close(); }}]);
                                         popbox.open();
                                     }
                                     $('workspinner').fade('out');
                                     enable_repos_controls(pathid);
                                     updatelock = false;
                                 }
                               });
    req.send({id: pathid});

    return false;
}


function do_delete_repos(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request({ url: api_request_path("dashboard", "dowebnuke"),
                            method: 'post',
                            onRequest: function() {
                                $('workspinner').fade('in');
                                disable_repos_controls(pathid);
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
                                enable_repos_controls(pathid);
                                updatelock = false;
                            }
                          });
    req.send({id: pathid});

    return false;
}


function change_repos(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "websetcheck"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspinner').fade('in');
                                     disable_repos_controls(pathid);
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);

                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                     // No error, post was edited, the element provided should
                                     // be the new <li>...
                                     } else {
                                         $('poptitle').set('text', respTree[0].get('text'));
                                         $('popbody').empty().grab(respTree[2]); // will remove respTree[2]!
                                         popbox.setButtons([{title: respTree[3].get('text'), color: 'red', event: function() { do_change_repos(pathid) } },
                                                            {title: respTree[5].get('text'), color: 'blue', event: function() { popbox.close(); }}]);
                                         popbox.open();
                                     }
                                     $('workspinner').fade('out');
                                     enable_repos_controls(pathid);
                                     updatelock = false;
                                 }
                               });
    req.send();

    return false;
}


function do_change_repos(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request({ url: api_request_path("dashboard", "dowebchange"),
                            method: 'post',
                            onRequest: function() {
                                $('workspinner').fade('in');
                                disable_repos_controls(pathid);
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
                                enable_repos_controls(pathid);
                                updatelock = false;
                            }
                          });
    req.send({'web-repos': $('web-repos').get('value'),
              id: pathid});

    return false;
}


function change_password()
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "dbsetcheck"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('dbworkspinner').fade('in');
                                     disable_database_controls();
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);

                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                     // No error, post was edited, the element provided should
                                     // be the new <li>...
                                     } else {
                                         $('poptitle').set('text', respTree[0].get('text'));
                                         $('popbody').empty().grab(respTree[2]); // will remove respTree[2]!
                                         popbox.setButtons([{title: respTree[3].get('text'), color: 'blue', event: function() { do_change_password() } },
                                                            {title: respTree[5].get('text'), color: 'blue', event: function() { popbox.close(); }}]);
                                         popbox.open();
                                     }
                                     $('dbworkspinner').fade('out');
                                     enable_database_controls();
                                     updatelock = false;
                                 }
                               });
    req.send();

    return false;
}


function do_change_password()
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request({ url: api_request_path("dashboard", "dodbchange"),
                            method: 'post',
                            onRequest: function() {
                                $('dbworkspinner').fade('in');
                                disable_database_controls();
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
                                $('dbworkspinner').fade('out');
                                enable_database_controls();
                                updatelock = false;
                            }
                          });
    req.send({'db-pass': $('db-pass').get('value'),
              'db-conf': $('db-conf').get('value')});

    return false;
}


function delete_database()
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "dbnukecheck"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('dbworkspinner').fade('in');
                                     disable_database_controls();
                                 },
                                 onSuccess: function(respTree, respElems, respHTML) {
                                     var err = respHTML.match(/^<div id="apierror"/);

                                     if(err) {
                                         $('errboxmsg').set('html', respHTML);
                                         errbox.open();

                                     // No error, post was edited, the element provided should
                                     // be the new <li>...
                                     } else {
                                         $('poptitle').set('text', respTree[0].get('text'));
                                         $('popbody').empty().grab(respTree[2]); // will remove respTree[2]!
                                         popbox.setButtons([{title: respTree[3].get('text'), color: 'red', event: function() { do_delete_database() } },
                                                            {title: respTree[5].get('text'), color: 'blue', event: function() { popbox.close(); }}]);
                                         popbox.open();
                                     }
                                     $('dbworkspinner').fade('out');
                                     enable_database_controls();
                                     updatelock = false;
                                 }
                               });
    req.send();

    return false;
}

function do_delete_database()
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request({ url: api_request_path("dashboard", "dodbnuke"),
                            method: 'post',
                            onRequest: function() {
                                $('dbworkspinner').fade('in');
                                disable_database_controls();
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
                                $('dbworkspinner').fade('out');
                                enable_database_controls();
                                updatelock = false;
                            }
                          });
    req.send();

    return false;
}


window.addEvent('domready', function()
{
    if($('web-repos'))
        new OverText('web-repos', { poll: true });

    if($('notebox'))
        setTimeout(function() { $('notebox').dissolve() }, 8000);

    enable_database_controls();

    $$('a.rel').each(function(element) {
                         element.addEvent('click',
                                          function (e) {
                                              e.stop();
                                              window.open(element.href);
                                          });
                     });
});
