const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('Gridfinity_Toolpath.htm', 'utf8');
const script = html.match(/<script type="text\/javascript">([\s\S]*?)<\/script>/)[1];

function dialog() {
  const values = {
    OverallX: '294', OverallY: '336', Columns: '7', Rows: '8',
    CellWidth: '42', CellHeight: '42'
  };
  const elements = {};
  for (const [id, value] of Object.entries(values)) {
    elements[id] = {
      value, style: {}, setAttribute() {}, removeAttribute() {}
    };
  }
  for (const id of ['OverallSizeChoice', 'GridSizeChoice', 'OverallSizeTitle',
                    'GridSizeTitle', 'SizingDescription']) {
    elements[id] = {style: {}, innerHTML: ''};
  }
  elements.OutputTypeRadio1 = {checked: false};
  elements.OutputTypeRadio2 = {checked: true};
  elements.SizeModeRadio1 = {checked: true};
  elements.SizeModeRadio2 = {checked: false};
  const context = vm.createContext({document: {getElementById: id => elements[id]}});
  vm.runInContext(script, context);
  return {elements, updateSizing: context.updateSizing};
}

let state = dialog();
state.elements.OverallX.value = '307';
state.updateSizing(null, 'overall');
assert.equal(Number(state.elements.Columns.value), 7);
state.elements.OverallY.value = '354';
state.updateSizing(null, 'overall');
assert.equal(Number(state.elements.Rows.value), 8);
state.elements.Columns.value = '6';
state.updateSizing(null, 'grid');
assert.equal(state.elements.OverallX.value, '307');
assert.equal(state.elements.OverallY.value, '354');

state = dialog();
state.elements.Columns.value = '7';
state.updateSizing(null, 'grid');
state.elements.Rows.value = '8';
state.updateSizing(null, 'grid');
assert.equal(state.elements.OverallX.value, '294.000');
assert.equal(state.elements.OverallY.value, '336.000');
state.elements.OverallX.value = '307';
state.updateSizing(null, 'overall');
assert.equal(state.elements.Columns.value, '7');
assert.equal(state.elements.Rows.value, '8');

console.log('Gridfinity dialog sizing tests passed');
