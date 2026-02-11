/**
 * Created by moskitos80 on 23.08.14.
 */
var DynamicTable = (function (GLOB) {
    var RID = 0;
    return function (tBody) {
        /* Если ф-цию вызвали не как конструктор фиксим этот момент: */
        if (!(this instanceof arguments.callee)) {
            return new arguments.callee.apply(arguments);
        }
        //Делегируем прослушку событий элементу tbody
        tBody.onclick = function(e) {
            var evt = e || GLOB.event,
                trg = evt.target || evt.srcElement;
            if (trg.className && trg.className.indexOf("check") !== -1) {
                _checkRow(trg.parentNode.parentNode, tBody);
            } else if (trg.className && trg.className.indexOf("add") !== -1) {
                _addRow(trg.parentNode.parentNode, tBody);
            } else if (trg.className && trg.className.indexOf("del") !== -1) {
                tBody.rows.length > 2 && _delRow(trg.parentNode.parentNode, tBody);
            } else if (trg.className && trg.className.indexOf("rescan") !== -1) {
                _rescan();
            }
        };
        var _rowTpl = tBody.rows[0].cloneNode(true);
        // Корректируем имена элементов формы
        var _correctNames = function (row) {
            var elements = row.getElementsByTagName("*");
            for (var i = 0; i < elements.length; i += 1) {
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
                        elements.item(j).name === "number[]")
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
                    elements.item(j).name === "ip[]" &&
                    elements.item(j).value !== "")
                {
                    //alert(elements.item(j).value);
                    var xhr = new XMLHttpRequest();
                    xhr.open("POST", window.location, true);
                    xhr.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
                    xhr.onreadystatechange = function() {
                        if (this.readyState != 4) return;
                        if (this.status != 200) {
                            // обработать ошибку
                            alert( 'ошибка: ' + (this.status ? this.statusText : 'запрос не удался') );
                            return;
                        }
                        // получить результат из this.responseText или this.responseXML
                        var ans = this.responseText;
                        alert(ans);
                        for (var i = 0; i < elements.length; i += 1) {
                            if (elements.item(i).id && elements.item(i).id === "status") {
                                 if (ans === "check_ok") {
                                     elements.item(i).innerText = "Ок";
                                     break;
                                 } else {
                                     elements.item(i).innerText = "Ошибка";
                                     break;
                                 }
                            }
                        }
                    }
                    xhr.send("check=1&ip="+ elements.item(j).value);
                    break;
                }
            }
            //window.location.href='config_bakup';
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
                    // обработать ошибку
                    alert( 'ошибка: ' + (this.status ? this.statusText : 'запрос не удался') );
                    return;
                }
                // получить результат из this.responseText или this.responseXML
                var ans = JSON.parse(this.responseText);
                for (var i = 0; i < tBody.rows.length; i += 1) {
                    var row = tBody.rows[i];
                    var elements = row.getElementsByTagName("*");
                    var mac = null;
                    for (var j = 0; j < elements.length; j += 1) {
                        if (elements.item(j).type &&
                            elements.item(j).type === "text" &&
                            elements.item(j).name === "mac[]")
                        {
                            var c = elements.item(j).value;
                            c = c.toUpperCase();
                            if (c in ans) {
                                mac = c;
                            }
                        } else if (mac &&
                            elements.item(j).type &&
                            elements.item(j).type === "text" &&
                            elements.item(j).name === "ip[]")
                        {
                            elements.item(j).value = ans[mac].ip;
                        } else if (mac &&
                            elements.item(j).type &&
                            elements.item(j).type === "text" &&
                            elements.item(j).name === "vendor[]")
                        {
                            elements.item(j).value = ans[mac].vendor;
                        } else if (mac &&
                            elements.item(j).id && 
                            elements.item(j).id === "status")
                        {
                            elements.item(j).innerText = "Ок";
                        }
                    }
                    if (mac) {
                        delete ans[mac];
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
                            elements.item(j).name === "mac[]")
                        {
                             elements.item(j).value = ans[key].mac;
                        } else if (elements.item(j).type &&
                            elements.item(j).type === "text" &&
                            elements.item(j).name === "ip[]")
                        {
                            elements.item(j).value = ans[key].ip;
                        } else if (elements.item(j).type &&
                            elements.item(j).type === "text" &&
                            elements.item(j).name === "vendor[]")
                        {
                            elements.item(j).value = ans[key].vendor;
                        } else if (elements.item(j).id &&
                            elements.item(j).id === "status")
                        {
                            elements.item(j).innerText = "Ок";
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
