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
            if (trg.className && trg.className.indexOf("add") !== -1) {
                tBody.rows.length < 5 && _addRow(trg.parentNode.parentNode, tBody);
            } else if (trg.className && trg.className.indexOf("del") !== -1) {
                tBody.rows.length > 1 && _delRow(trg.parentNode.parentNode, tBody);
            }
        };
        var _rowTpl = tBody.rows[0].cloneNode(true);
        // Корректируем имена элементов формы
        var _correctNames = function (row) {
            var elements = row.getElementsByTagName("*");
            for (var i = 0; i < elements.length; i += 1) {
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
        var _addRow = function (before, tBody) {
            var newNode = _correctNames(_rowTpl.cloneNode(true));
            tBody.insertBefore(newNode, before.nextSibling);
            _updateTableNumeration();
        };
        var _delRow = function (row, tBody) {
            tBody.removeChild(row);
            _updateTableNumeration();
        };
    };
})(this);
