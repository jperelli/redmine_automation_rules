module AutomationRulesHelper
  # Redmine 6 ships an SVG sprite and the sprite_icon helper; Redmine 5 has
  # neither, so fall back to the label with the classic CSS icon class.
  def automation_rules_sprite_icon(icon, label, icon_only: false)
    if respond_to?(:sprite_icon)
      sprite_icon(icon, label, icon_only: icon_only)
    else
      icon_only ? '' : label
    end
  end
end
