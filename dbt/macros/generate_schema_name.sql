{#
  Use the custom schema name exactly (silver, gold, marts, quarantine), without the
  default "<target_schema>_" prefix. Models without a custom schema use the target schema.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
