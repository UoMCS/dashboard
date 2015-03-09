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
        $('updatebtn-'+id).addEvent('click', function() { update_repos(id); }).removeClass('disabled');

    if($('remotebtn-'+id))
        $('remotebtn-'+id).addEvent('click', function() { show_token(id); }).removeClass('disabled');

    if($('deletebtn-'+id))
        $('deletebtn-'+id).addEvent('click', function() { delete_repos(id); }).removeClass('disabled');

    if($('changebtn-'+id))
        $('changebtn-'+id).addEvent('click', function() { change_repos(id); }).removeClass('disabled');
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
                                     $('workspinner-'+pathid).fade('in');
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
                                     $('workspinner-'+pathid).fade('out');
                                     enable_repos_controls(pathid);
                                     updatelock = false;
                                 }
                               });
    req.post({'id': pathid});

    return false;
}


function update_repos(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "pullrepo"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspinner-'+pathid).fade('in');
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

                                     $('workspinner-'+pathid).fade('out');
                                     enable_repos_controls(pathid);
                                     updatelock = false;
                                 }
                               });
    req.post({'id': pathid});

    return false;
}


function delete_repos(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "webnukecheck"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspinner-'+pathid).fade('in');
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

                                         new Element("img", {   'id': 'popspinner',
                                                                'src': spinner_url,
                                                                width: 16,
                                                                height: 16,
                                                                'class': 'workspin'}).inject(popbox.footer, 'top');
                                         popbox.open();
                                     }
                                     $('workspinner-'+pathid).fade('out');
                                     enable_repos_controls(pathid);
                                     updatelock = false;
                                 }
                               });
    req.post({'id': pathid});

    return false;
}


function do_delete_repos(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request({ url: api_request_path("dashboard", "dowebnuke"),
                            method: 'post',
                            onRequest: function() {
                                $('workspinner-'+pathid).fade('in');
                                $('popspinner').fade('in');
                                disable_repos_controls(pathid);
                                popbox.disableButtons(true);
                            },
                            onSuccess: function(respText, respXML) {
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    popbox.close();
                                    errbox.open();
                                } else {
                                    $('site-'+pathid).fade('out').get('tween').chain(function() {
                                        $('site-'+pathid).destroy();
                                    });
                                }
                                popbox.close();
                                $('workspinner-'+pathid).fade('out');
                                enable_repos_controls(pathid);
                                updatelock = false;
                            }
                          });
    req.post({'id': pathid});

    return false;
}


function change_repos(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request.HTML({ url: api_request_path("dashboard", "websetcheck"),
                                 method: 'post',
                                 onRequest: function() {
                                     $('workspinner-'+pathid).fade('in');
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
                                         new Element("img", {  'id': 'popspinner',
                                                              'src': spinner_url,
                                                              width: 16,
                                                             height: 16,
                                                            'class': 'workspin'}).inject(popbox.footer, 'top');
                                         popbox.open();
                                     }
                                     $('workspinner-'+pathid).fade('out');
                                     enable_repos_controls(pathid);
                                     updatelock = false;
                                 }
                               });
    req.post();

    return false;
}


function do_change_repos(pathid)
{
    if(updatelock) return false;
    updatelock = true;

    var req = new Request({ url: api_request_path("dashboard", "dowebchange"),
                            method: 'post',
                            onRequest: function() {
                                $('workspinner-'+pathid).fade('in');
                                $('popspinner').fade('in');
                                disable_repos_controls(pathid);
                                popbox.disableButtons(true);
                            },
                            onSuccess: function(respText, respXML) {
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    popbox.close();
                                    errbox.open();
                                } else {
                                    var res = respXML.getElementsByTagName("result")[0];
                                    var repos = res.getAttribute("repos");

                                    $('source-'+pathid).set('html', repos);
                                }
                                popbox.close();
                                $('workspinner-'+pathid).fade('out');
                                enable_repos_controls(pathid);
                                updatelock = false;
                            }
                          });
    req.post({'web-repos': $('web-change').get('value'),
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
                                         new Element("img", {   'id': 'popspinner',
                                                               'src': spinner_url,
                                                               width: 16,
                                                              height: 16,
                                                             'class': 'workspin'}).inject(popbox.footer, 'top');
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
                                $('popspinner').fade('in');
                                popbox.disableButtons(true);
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
    req.post({'db-pass': $('db-pass').get('value'),
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
                                         new Element("img", {   'id': 'popspinner',
                                                               'src': spinner_url,
                                                               width: 16,
                                                              height: 16,
                                                             'class': 'workspin'}).inject(popbox.footer, 'top');
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
                                $('popspinner').fade('in');
                                popbox.disableButtons(true);
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


function autoset_project_dir(projfield, dirfield)
{
    var setproj  = projfield.get('value');
    var projname = /\/([^\/]+)\.git\s*$/;

    if(setproj) {
        var result = projname.exec(setproj);
        if(result && result[1]) {
            var result = result[1].replace(/ /g, '_');
            dirfield.set('value', result);
        }
    }
}


function set_primary_project(projfield, spinner)
{
    var selected = projfield.getSelected()[0].get('value');

    var req = new Request({ url: api_request_path("dashboard", "setprimary"),
                            method: 'post',
                            onRequest: function() {
                                projfield.disabled = true;
                                spinner.fade('in');
                            },
                            onSuccess: function(respText, respXML) {
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    popbox.close();
                                    errbox.open();
                                }
                                spinner.fade('out');
                                projfield.disabled = false;
                            }
                          });
    req.post({'primary': selected});
}


function enable_extradb_form()
{
    $('createdb').addEvent('click', function() { add_extra_database(); });

    // Dropdowns to select which database to use for each project
    $$('select.projdb').each(function(element) { element.addEvent('change', function(event) { set_project_database(event.target); })
                                               });

    // Delete buttons for extra databases
    $$('div.control.deldb').each(function(element) { element.addEvent('click', function(event) { delete_extra_database(event.target); })
                                                   });
}


function add_extra_database()
{
     var req = new Request({ url: api_request_path("dashboard", "adddb"),
                            method: 'post',
                            onRequest: function() {
                                $('createdb').set('disabled', true);
                                $('createdb').addClass('disabled');
                            },
                            onSuccess: function(respText, respXML) {
                                $('createdb').set('disabled', false);
                                $('createdb').removeClass('disabled');
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();
                                } else {
                                    var res = respXML.getElementsByTagName("return")[0];
                                    var rup = res.getAttribute("url");

                                    if(rup)
                                        location.href = rup;
                                }
                            }
                           });
    var name   = $('extradb-name').get('value');
    var source = $('extradb-source').getSelected()[0].get('value');
    req.post({extraname: name,
              extrasrc: source});
}


function delete_extra_database(element)
{
    var dbname = element.get('id').substr(9);
    var req = new Request({ url: api_request_path("dashboard", "deldb"),
                            method: 'post',
                            onRequest: function() {
                                $('workspinner-'+dbname).fade('in');
                            },
                            onSuccess: function(respText, respXML) {
                                $('workspinner-'+dbname).fade('out');
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();
                                } else {
                                    // remove the row in the table
                                    $('extradb-'+dbname).fade('out').get('tween').chain(function() {
                                        $('extradb-'+dbname).destroy();
                                    });

                                    // And the entry in the source dropdown
                                    $$('select.sourcedb option[value="'+dbname+'"]').each(function(element) { element.remove(); });

                                    // and any databases set for projects
                                    $$('select.projdb option[value="'+dbname+'"]').each(function(element) {
                                        var select = element.getParent();

                                        // The first option is always the user's default database, which can not be deleted.
                                        select.value = select.options[0].get('value');

                                        element.remove();
                                    });
                                }

                            }
                          });

    req.post({dbname: dbname});
}


function set_project_database(element)
{
    var pathid = element.get('id').substr(8);

    var req = new Request({ url: api_request_path("dashboard", "setprojdb"),
                            method: 'post',
                            onRequest: function() {
                                element.set('disabled', true);
                                $('workspinner-'+pathid).fade('in');
                                disable_repos_controls(pathid);
                            },
                            onSuccess: function(respText, respXML) {
                                element.set('disabled', false);
                                $('workspinner-'+pathid).fade('out');
                                enable_repos_controls(pathid);
                                var err = respXML.getElementsByTagName("error")[0];

                                if(err) {
                                    $('errboxmsg').set('html', '<p class="error">'+err.getAttribute('info')+'</p>');
                                    errbox.open();
                                }
                            }
                          });
    var dbname = element.getSelected()[0].get('value');
    req.post({project: pathid,
              dbname: dbname});
}

window.addEvent('domready', function()
{
    if($('web-repos'))
        new OverText('web-repos', { wrap: true});

    if($('web-path'))
        new OverText('web-path', { wrap: true,
                                   poll: true});

    if($('web-primary'))
        $('web-primary').addEvent('change', function () { set_primary_project($('web-primary'), $('workspin-primary')); });

    if($('web-repos'))
        $('web-repos').addEvent('change', function () { autoset_project_dir($('web-repos'), $('web-path')); });

    if($('notebox'))
        setTimeout(function() { $('notebox').dissolve() }, 8000);

    $$('ul.controls.website').each(function(element) {
        var id = element.get('id').substr(5);
        enable_repos_controls(id);
    });

    enable_database_controls();

    if($('extradbs')) {
        enable_extradb_form();
    }

    $$('a.rel').each(function(element) {
                         element.addEvent('click',
                                          function (e) {
                                              e.stop();
                                              window.open(element.href);
                                          });
                     });
});
