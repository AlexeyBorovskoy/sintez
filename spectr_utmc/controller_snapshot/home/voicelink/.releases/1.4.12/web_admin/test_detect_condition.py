# -*- coding: utf-8 -*-

s = "((1|2)&!3)"
integer = ''
result = ''
inputs = [[0,0],[0,1],[0,0]]

for n in s:
    if n.isdigit():
        integer += n
    else:
        if integer:
            for i, d in enumerate(inputs, start=1):
                if i == int(integer):
                    if 1 in d:
                        result += '1'
                    else:
                        result += '0'
                    break
            else:
                result += '0'
            integer = ''
        result += n

result = result.replace('|',' or ').replace('&',' and ').replace('!',' not ')

print(result, bool(eval(result)))

def brackets_check(s):
    """Возвращает 3 значения:
    0 - все ок
    <0 - не хватает открывающейся скобки '('
    >0 - не хватает закрывающейся скобки ')' """
    counter = 0
    for c in s:
        if c == '(':
            counter += 1
        elif c == ')':
            counter -= 1
            if counter < 0:
                ##return False
                break
    print('counter =', counter)
    ##return counter == 0
    return counter


r = brackets_check("((((()))))(((()))")
if r == 0:
    print('ok')
elif r > 0:
    print('lacks bracket ")"')
elif r < 0:
    print('lacks bracket "("')
