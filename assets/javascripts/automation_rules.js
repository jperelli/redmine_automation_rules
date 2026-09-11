/* Automation Rules plugin: plain JS on top of Redmine's jQuery, no build step.
 *
 * The rule form renders its condition and action rows client side from the
 * schema served by AutomationRulesController#fields (types, parameters and
 * option lists for the project). Rows are posted as
 * automation_rule[conditions][N][param] / automation_rule[actions][N][param].
 */
(function () {
  'use strict';

  window.AutomationRules = window.AutomationRules || {};

  var Form = {
    schema: null,
    counters: { conditions: 0, actions: 0 },

    init: function ($form) {
      if (!$form.length) { return; }
      this.$form = $form;
      var $fields = $form.find('.automation-rule-fields');
      var self = this;
      this.initial = {
        conditions: $fields.data('conditions') || [],
        actions: $fields.data('actions') || []
      };
      this.bindTrigger();
      this.bindSubmit();
      $.getJSON($fields.data('fields-url'), function (schema) {
        self.schema = schema;
        self.renderInitialRows();
        self.bindAddButtons();
        self.bindSortable();
      });
    },

    /* Rows are posted in DOM order: renumber the indexes right before submit. */
    bindSubmit: function () {
      var self = this;
      this.$form.on('submit', function () {
        $.each(['conditions', 'actions'], function (_, kind) {
          self.$form.find('#automation-rule-' + kind + ' .automation-rule-row').each(function (position) {
            $(this).find('[name]').each(function () {
              var name = $(this).attr('name').replace(/^automation_rule\[\w+\]\[\d+\]/, 'automation_rule[' + kind + '][' + position + ']');
              $(this).attr('name', name);
            });
          });
        });
      });
    },

    bindSortable: function () {
      var $containers = this.$form.find('#automation-rule-conditions, #automation-rule-actions');
      if ($.fn.sortable) {
        $containers.sortable({ handle: '.automation-rule-row-handle', axis: 'y', items: '.automation-rule-row' });
      }
    },

    /* --- trigger --- */

    bindTrigger: function () {
      var self = this;
      var $type = this.$form.find('#automation_rule_trigger_type');
      $type.on('change', function () { self.updateTrigger(); });
      this.$form.find('#trigger_change').on('change', function () { self.updateTrigger(); });
      this.$form.find('#trigger_interval_unit').on('change', function () { self.updateTrigger(); });
      this.updateTrigger();
    },

    updateTrigger: function () {
      var type = this.$form.find('#automation_rule_trigger_type').val();
      this.$form.find('.automation-rule-trigger-options').each(function () {
        $(this).toggle($(this).data('trigger') === type);
      });
      var change = this.$form.find('#trigger_change').val();
      this.$form.find('.automation-rule-change-option').each(function () {
        $(this).toggle($(this).data('change') === change);
      });
      var unit = this.$form.find('#trigger_interval_unit').val();
      this.$form.find('.automation-rule-time-of-day').toggle(unit === 'day' || unit === 'week');
    },

    /* --- rows --- */

    renderInitialRows: function () {
      var self = this;
      $.each(['conditions', 'actions'], function (_, kind) {
        var $container = self.$form.find('#automation-rule-' + kind);
        $container.empty();
        $.each(self.initial[kind], function (_, row) { self.addRow(kind, row); });
      });
    },

    bindAddButtons: function () {
      var self = this;
      this.$form.find('.automation-rule-add').on('click', function (e) {
        e.preventDefault();
        var kind = $(this).data('kind');
        var $row = self.addRow(kind, {});
        $row.find('select.automation-rule-type').trigger('focus');
      });
    },

    definitions: function (kind) {
      return this.schema[kind] || [];
    },

    definition: function (kind, type) {
      var found = null;
      $.each(this.definitions(kind), function (_, def) {
        if (def.key === type) { found = def; }
      });
      return found;
    },

    addRow: function (kind, values) {
      var index = this.counters[kind]++;
      var self = this;
      var $row = $('<div class="automation-rule-row"></div>').attr('data-kind', kind).attr('data-index', index);
      var $handle = $('<span class="automation-rule-row-handle" title="' + this.label('button_sort') + '">&#8942;</span>');
      var $type = $('<select class="automation-rule-type"></select>')
        .attr('name', this.paramName(kind, index, 'type'));
      $type.append($('<option></option>').attr('value', '').text(this.label('select')));
      $.each(this.definitions(kind), function (_, def) {
        $type.append($('<option></option>').attr('value', def.key).text(def.label));
      });
      $type.val(values.type || '');
      var $params = $('<span class="automation-rule-params"></span>');
      var $remove = $('<a href="#" class="icon-only icon-del automation-rule-remove"></a>')
        .attr('title', this.label('button_delete'))
        .text(this.label('button_delete'));

      $row.append($handle).append($type).append($params).append($remove);
      this.$form.find('#automation-rule-' + kind).append($row);

      $type.on('change', function () {
        self.renderParams($row, {});
      });
      $remove.on('click', function (e) {
        e.preventDefault();
        $row.remove();
      });
      this.renderParams($row, values);
      return $row;
    },

    /* Collects current param values of a row from its inputs. */
    rowValues: function ($row) {
      var values = {};
      $row.find('.automation-rule-params [name]').each(function () {
        var $input = $(this);
        var name = $input.data('param');
        if ($input.is(':checkbox')) {
          values[name] = $input.is(':checked') ? '1' : '0';
        } else {
          values[name] = $input.val();
        }
      });
      return values;
    },

    renderParams: function ($row, values) {
      var kind = $row.data('kind');
      var index = $row.data('index');
      var type = $row.find('select.automation-rule-type').val();
      var def = this.definition(kind, type);
      var $params = $row.find('.automation-rule-params');
      var self = this;
      $params.empty();
      if (!def) { return; }

      values = $.extend({}, values);
      $.each(def.params, function (_, param) {
        if (!self.paramVisible(param, values)) { return; }
        var $widget = self.buildWidget(kind, index, param, values, $row);
        if (!$widget) { return; }
        if (param.label) {
          var $label = $('<label class="automation-rule-param-label"></label>').text(param.label);
          $params.append($label);
        }
        $params.append($widget);
        /* Later params may depend on the value a select defaulted to. */
        $.extend(values, self.rowValues($row));
      });
    },

    paramVisible: function (param, values) {
      if (!param.when) { return true; }
      var visible = true;
      $.each(param.when, function (name, allowed) {
        var value = values[name];
        if (value === undefined || value === null) {
          visible = false;
          return;
        }
        if ($.inArray(String(value), allowed) === -1) { visible = false; }
      });
      return visible;
    },

    paramName: function (kind, index, name) {
      return 'automation_rule[' + kind + '][' + index + '][' + name + ']';
    },

    buildWidget: function (kind, index, param, values, $row) {
      var self = this;
      var name = this.paramName(kind, index, param.name);
      var value = values[param.name];
      var $widget;
      switch (param.widget) {
        case 'select':
          $widget = this.buildSelect(this.optionsFor(param.options), value, param.required);
          break;
        case 'custom_field_value':
          $widget = this.buildCustomFieldValue(values.custom_field_id, value);
          break;
        case 'textarea':
          $widget = $('<textarea rows="3" cols="50"></textarea>').val(value || '');
          break;
        case 'number':
          $widget = $('<input type="number" size="6" />').val(value === undefined ? '' : value);
          break;
        case 'date':
          $widget = $('<input type="date" size="10" />').val(value || '');
          break;
        case 'checkbox':
          $widget = $('<input type="checkbox" value="1" />').prop('checked', String(value) === '1');
          break;
        default:
          $widget = $('<input type="text" size="30" />').val(value || '');
      }
      if (!$widget) { return null; }
      var $inputs = $widget.is('[name], select, input, textarea') ? $widget : $widget.find('select, input, textarea');
      $inputs.attr('name', name).attr('data-param', param.name).addClass('automation-rule-param');
      if (param.placeholder) { $inputs.attr('placeholder', param.placeholder); }
      $inputs.on('change', function () {
        /* Other params may depend on this one (operator, custom field...). */
        self.renderParams($row, self.rowValues($row));
      });
      return $widget;
    },

    optionsFor: function (options) {
      if (Array.isArray(options)) { return options; }
      return (this.schema.options && this.schema.options[options]) || [];
    },

    buildSelect: function (options, value, required) {
      var $select = $('<select></select>');
      if (!required || value === undefined || value === null || value === '') {
        $select.append($('<option></option>').attr('value', '').text(''));
      }
      $.each(options, function (_, pair) {
        $select.append($('<option></option>').attr('value', pair[1]).text(pair[0]));
      });
      if (value === undefined || value === null || value === '') {
        if (required && options.length) { $select.val(String(options[0][1])); }
      } else {
        $select.val(String(value));
      }
      return $select;
    },

    customField: function (id) {
      var found = null;
      $.each(this.schema.custom_fields || [], function (_, cf) {
        if (String(cf.id) === String(id)) { found = cf; }
      });
      return found;
    },

    buildCustomFieldValue: function (customFieldId, value) {
      var cf = this.customField(customFieldId);
      if (!cf) { return $('<input type="text" size="30" />').val(value || ''); }
      switch (cf.format) {
        case 'list':
        case 'bool':
        case 'user':
        case 'version':
        case 'enumeration':
          return this.buildSelect(cf.possible_values, value, false);
        case 'date':
          return $('<input type="date" size="10" />').val(value || '');
        case 'int':
        case 'float':
          return $('<input type="number" size="10" step="any" />').val(value === undefined ? '' : value);
        default:
          return $('<input type="text" size="30" />').val(value || '');
      }
    },

    label: function (key) {
      var labels = (this.schema && this.schema.labels) || {};
      return labels[key] || key;
    }
  };

  window.AutomationRules.Form = Form;

  // "New rule from recipe" select on the rule list: opens the new-rule form
  // pre-filled with the chosen recipe.
  $(document).on('change', '.automation-rule-recipe-select', function () {
    var key = $(this).val();
    if (!key) { return; }
    var url = $(this).data('url');
    window.location.href = url + (url.indexOf('?') === -1 ? '?' : '&') + 'recipe=' + encodeURIComponent(key);
  });
})();
