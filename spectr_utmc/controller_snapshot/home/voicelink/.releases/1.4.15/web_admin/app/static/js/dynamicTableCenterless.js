/**
 * Created by moskitos80 on 23.08.14.
 */
var DynamicTableCenterless = (function (GLOB) {
    var RID = 0;
    return function (tBody) {
        /* Если ф-цию вызвали не как конструктор фиксим этот момент: */
        if (!(this instanceof arguments.callee)) {
            return new arguments.callee.apply(arguments);
        }
        /*Делегируем прослушку событий элементу tbody */
        tBody.onclick = function(e) {
            var evt = e || GLOB.event,
                trg = evt.target || evt.srcElement;
            if (trg.className && trg.className.indexOf("check") !== -1) {
                _checkRow(trg.parentNode.parentNode, tBody);
            } else if (trg.className && trg.className.indexOf("add") !== -1) {
                tBody.rows.length < 16 && _addRow(trg.parentNode.parentNode, tBody);
            } else if (trg.className && trg.className.indexOf("del") !== -1) {
                tBody.rows.length > 2 && _delRow(trg.parentNode.parentNode, tBody);
            } else if (trg.className && trg.className.indexOf("rescan") !== -1) {
                _rescan();
            }
        };
        var _rowTpl = tBody.rows[0].cloneNode(true);
        /* Корректируем имена элементов формы */
        var _correctNames = function (row) {
            var elements = row.getElementsByTagName("*");
            for (var i = 0; i < elements.length; i += 1) {
                if (elements.item(i).id &&
                    elements.item(i).id === "status_link")
                {
                    elements.item(i).innerText = "";
                }
                if (elements.item(i).id &&
                    elements.item(i).id === "status")
                {
                    elements.item(i).innerText = "";
                }
                if (elements.item(i).name) {
                    if (elements.item(i).type &&
                        elements.item(i).type === "radio" &&
                        elements.item(i).className &&
                        elements.item(i).className.indexOf("glob") !== -1)
                    {
                        elements.item(i).value = RID;
                    } else if (elements.item(i).nodeName === "SELECT")
                    {
                        elements.item(i).value = 0;
                    } else {
                        elements.item(i).value = "";
                    }
                }
            }
            RID++;
            return row;
        };
        var _updateTableNumeration = function () {
            for (var i = 0; i < tBody.rows.length; i += 1) {
                var row = tBody.rows[i];
                var elements = row.getElementsByTagName("*");
                for (var j = 0; j < elements.length; j += 1) {
                    if (elements.item(j).type &&
                        elements.item(j).type === "hidden" &&
                        elements.item(j).name === "slave_number[]")
                    {
                        elements.item(j).value = row.rowIndex;
                    } else if (elements.item(j).id &&
                        elements.item(j).id === "enumerate")
                    {
                        elements.item(j).innerText = row.rowIndex;
                    }
                }
            }
        };
        var _checkRow = function (row, tBody) {
            var elements = row.getElementsByTagName("*");
            for (var j = 0; j < elements.length; j += 1) {
                if (elements.item(j).type &&
                    elements.item(j).type === "text" &&
                    elements.item(j).name === "slave_ip[]" &&
                    elements.item(j).value !== "")
                {
                    /* alert(elements.item(j).value); */
                    var xhr = new XMLHttpRequest();
                    xhr.open("POST", window.location, true);
                    xhr.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
                    xhr.onreadystatechange = function() {
                        if (this.readyState != 4) return;
                        if (this.status != 200) {
                            /* обработать ошибку */
                            /* alert( 'ошибка: ' + (this.status ? this.statusText : 'запрос не удался') ); */
                            return;
                        }
                        /* получить результат из this.responseText или this.responseXML */
                        var ans = JSON.parse(this.responseText);
                        /* alert(JSON.stringify(ans)); */
                        var ip = elements.item(j).value;
                        ip = ip.toUpperCase();
                        for (var i = 0; i < elements.length; i += 1) {
                            if (elements.item(i).id && elements.item(i).id === "status_link") {
                                if (ip && ans[ip][0] === 'check_ok') {
                                    elements.item(i).innerText = "connected";
                                } else {
                                    elements.item(i).innerText = "disconnected";
                                }
                            } else if (elements.item(i).id && elements.item(i).id === "status") {
                                if (ip && ans[ip][1] === 'check_ok') {
                                    elements.item(i).innerText = "configured";
                                } else {
                                    elements.item(i).innerText = "not configured";
                                }
                            }
                        }
                    }
                    xhr.send("check=1&ip="+ elements.item(j).value);
                    break;
                }
            }
        };
        var _addRow = function (before, tBody) {
            var newNode = _correctNames(_rowTpl.cloneNode(true));
            tBody.insertBefore(newNode, before.nextSibling);
            _updateTableNumeration();
        };
        var _delRow = function (row, tBody) {
            tBody.removeChild(row);
            _updateTableNumeration();
        };
        var _rescan = function () {
            var progressBar = document.getElementById("myBar")
            var modal = document.getElementById('myModal');
            modal.style.display = "block";
            var xhr = new XMLHttpRequest();
            xhr.open("POST", window.location, true);
            xhr.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
            xhr.onreadystatechange = function() {
                if (this.readyState != 4) return;
                if (this.status != 200) {
                    /* обработать ошибку */
                    alert( 'ошибка: ' + (this.status ? this.statusText : 'запрос не удался') );
                    modal.style.display = "none";
                    return;
                }
                /* получить результат из this.responseText или this.responseXML */
                try {
                    var ans = JSON.parse(this.responseText);
                } catch (err) {
                    alert(this.responseText);
                    alert(err.name);
                    alert(err.message);
                    alert(err.stack);
                    modal.style.display = "none";
                    return;
                }
                for (var i = 0; i < tBody.rows.length; i += 1) {
                    var row = tBody.rows[i];
                    var elements = row.getElementsByTagName("*");
                    var id = null;
                    var ip = null;
                    for (var j = 0; j < elements.length; j += 1) {
                        if (elements.item(j).type &&
                            elements.item(j).type === "text" &&
                            elements.item(j).name === "slave_id[]")
                        {
                            var c = elements.item(j).value;
                            c = c.toUpperCase();
                            if (c in ans) {
                                id = c;
                            }
                        } else if (elements.item(j).type &&
                            elements.item(j).type === "text" &&
                            elements.item(j).name === "slave_ip[]")
                        {
                            var c = elements.item(j).value;
                            c = c.toUpperCase();
                            if (c in ans) {
                                ip = c;
                            }
                        } else if (elements.item(j).id &&
                            elements.item(j).id === "status_link")
                        {
                            if (ip) {
                                elements.item(j).innerText = "connected";
                            } else {
                                elements.item(j).innerText = "disconnected";
                            }
                        } else if (elements.item(j).id &&
                            elements.item(j).id === "status")
                        {
                            if (ip && ans[ip].centerless_control.control_mode === "slave" && ans[ip].centerless_control.slave.master_ip === ans[ip].host) {
                                elements.item(j).innerText = "configured";
                            } else {
                                elements.item(j).innerText = "not configured";
                            }
                        }
                    }
                    if (id) {
                        delete ans[id];
                    }
                    if (ip) {
                        delete ans[ip];
                    }

                }
                for (key in ans) {
                    var row = tBody.rows[tBody.rows.length-2];
                    _addRow(row, tBody);
                    var row = tBody.rows[tBody.rows.length-2];
                    var elements = row.getElementsByTagName("*");
                    for (var j = 0; j < elements.length; j += 1) {
                        if (elements.item(j).type &&
                            elements.item(j).type === "text" &&
                            elements.item(j).name === "slave_ip[]")
                        {
                            elements.item(j).value = ans[key].ip;
                        } else if (elements.item(j).id &&
                            elements.item(j).id === "status_link")
                        {
                            if (ans[key].ip) {
                                elements.item(j).innerText = "connected";
                            } else {
                                elements.item(j).innerText = "disconnected";
                            }
                        } else if (elements.item(j).id &&
                            elements.item(j).id === "status")
                        {
                            if (ans[key].centerless_control.control_mode === "slave") {
                                elements.item(j).innerText = "configured";
                            } else {
                                elements.item(j).innerText = "not configured";
                            }
                        }
                    }
                }
                alert(JSON.stringify(ans));
                modal.style.display = "none";
            }
            xhr.send("rescan=1");
        };
    };
})(this);
