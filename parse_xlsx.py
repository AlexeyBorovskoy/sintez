#!/usr/bin/env python3
"""
Парсинг Excel файла через XML (без библиотек)
"""

import xml.etree.ElementTree as ET
import re
import sys

xlsx_dir = "/tmp/xlsx_extract"

# Читаем sharedStrings
shared_strings = []
try:
    tree = ET.parse(f"{xlsx_dir}/xl/sharedStrings.xml")
    root = tree.getroot()
    # Находим все текстовые значения
    for si in root.findall('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}si'):
        text = ""
        for t in si.findall('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t'):
            if t.text:
                text += t.text
        shared_strings.append(text)
except Exception as e:
    print(f"Ошибка чтения sharedStrings: {e}")

# Функция для получения значения ячейки
def get_cell_value(cell_elem, shared_strings):
    if cell_elem is None:
        return ""
    
    # Получаем тип и значение
    cell_type = cell_elem.get('t')
    value_elem = cell_elem.find('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}v')
    
    if value_elem is None:
        return ""
    
    value = value_elem.text
    
    if cell_type == 's' and value:  # Shared string
        try:
            idx = int(value)
            if 0 <= idx < len(shared_strings):
                return shared_strings[idx]
        except:
            pass
    
    return value if value else ""

# Читаем workbook для получения имен листов
sheet_names = []
try:
    tree = ET.parse(f"{xlsx_dir}/xl/workbook.xml")
    root = tree.getroot()
    for sheet in root.findall('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}sheet'):
        name = sheet.get('name', '')
        sheet_id = sheet.get('sheetId', '')
        r_id = sheet.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id', '')
        sheet_names.append((name, sheet_id, r_id))
except Exception as e:
    print(f"Ошибка чтения workbook: {e}")

print("="*80)
print("АНАЛИЗ EXCEL ФАЙЛА: Sintez_snmp_protocols(1).xlsx")
print("="*80)
print(f"\n📋 Найдено листов: {len(sheet_names)}\n")

# Маппинг sheetId -> имя файла
sheet_files = {}
for i in range(1, len(sheet_names) + 1):
    sheet_files[str(i)] = f"sheet{i}.xml"

# Читаем каждый лист
for sheet_name, sheet_id, r_id in sheet_names:
    print(f"\n{'='*80}")
    print(f"📄 ЛИСТ: {sheet_name}")
    print(f"{'='*80}\n")
    
    sheet_file = sheet_files.get(sheet_id, f"sheet{sheet_id}.xml")
    sheet_path = f"{xlsx_dir}/xl/worksheets/{sheet_file}"
    
    try:
        tree = ET.parse(sheet_path)
        root = tree.getroot()
        
        # Собираем все ячейки в словарь по координатам
        cells = {}
        for row_elem in root.findall('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}row'):
            row_num = int(row_elem.get('r', 0))
            for cell_elem in row_elem.findall('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}c'):
                cell_ref = cell_elem.get('r', '')
                if cell_ref:
                    # Парсим координаты (например, A1 -> (1, 1))
                    col_match = re.match(r'([A-Z]+)', cell_ref)
                    row_match = re.match(r'[A-Z]+(\d+)', cell_ref)
                    if col_match and row_match:
                        col_str = col_match.group(1)
                        row_num = int(row_match.group(1))
                        # Конвертируем колонку в число
                        col_num = 0
                        for char in col_str:
                            col_num = col_num * 26 + (ord(char) - ord('A') + 1)
                        cells[(row_num, col_num)] = get_cell_value(cell_elem, shared_strings)
        
        # Выводим таблицу
        if cells:
            max_row = max(r for r, c in cells.keys())
            max_col = max(c for r, c in cells.keys())
            
            print(f"Размер: {max_row} строк × {max_col} столбцов\n")
            print("Первые 20 строк:")
            print("-" * 80)
            
            for row in range(1, min(21, max_row + 1)):
                row_data = []
                for col in range(1, min(11, max_col + 1)):  # Первые 10 столбцов
                    value = cells.get((row, col), "")
                    if len(str(value)) > 30:
                        value = str(value)[:27] + "..."
                    row_data.append(str(value))
                if any(row_data):  # Показываем только непустые строки
                    print(f"{row:3d}: {' | '.join(f'{v:30s}' for v in row_data)}")
        else:
            print("Лист пуст или не удалось прочитать данные")
            
    except Exception as e:
        print(f"Ошибка чтения листа {sheet_name}: {e}")
    
    print()

print("\n" + "="*80)
print("АНАЛИЗ ЗАВЕРШЕН")
print("="*80)
