---
name: TindaTrack Utilitarian Monolith
colors:
  surface: '#f5fbf5'
  surface-dim: '#d5dcd6'
  surface-bright: '#f5fbf5'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#eff5ef'
  surface-container: '#e9efe9'
  surface-container-high: '#e4eae4'
  surface-container-highest: '#dee4de'
  on-surface: '#171d19'
  on-surface-variant: '#3d4a42'
  inverse-surface: '#2c322e'
  inverse-on-surface: '#ecf2ec'
  outline: '#6d7a72'
  outline-variant: '#bccac0'
  surface-tint: '#006c4a'
  primary: '#006948'
  on-primary: '#ffffff'
  primary-container: '#00855d'
  on-primary-container: '#f5fff7'
  inverse-primary: '#68dba9'
  secondary: '#565e74'
  on-secondary: '#ffffff'
  secondary-container: '#dae2fd'
  on-secondary-container: '#5c647a'
  tertiary: '#9b3e3b'
  on-tertiary: '#ffffff'
  tertiary-container: '#ba5551'
  on-tertiary-container: '#fffbff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#85f8c4'
  primary-fixed-dim: '#68dba9'
  on-primary-fixed: '#002114'
  on-primary-fixed-variant: '#005137'
  secondary-fixed: '#dae2fd'
  secondary-fixed-dim: '#bec6e0'
  on-secondary-fixed: '#131b2e'
  on-secondary-fixed-variant: '#3f465c'
  tertiary-fixed: '#ffdad7'
  tertiary-fixed-dim: '#ffb3ae'
  on-tertiary-fixed: '#410004'
  on-tertiary-fixed-variant: '#7f2928'
  background: '#f5fbf5'
  on-background: '#171d19'
  surface-variant: '#dee4de'
  status-in-stock: '#10B981'
  status-low-stock: '#F59E0B'
  status-out-of-stock: '#EF4444'
  action-destructive: '#B91C1C'
  surface-tonal: '#F8FAFC'
  surface-border: '#E2E8F0'
typography:
  display-price:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
  headline-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '500'
    lineHeight: 24px
  body-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '700'
    lineHeight: 16px
    letterSpacing: 0.05em
  numeric-keypad:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '500'
    lineHeight: 24px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  touch-target: 3rem
  gutter: 1rem
  stack-sm: 0.5rem
  stack-md: 1rem
  container-margin: 1rem
---

## Brand & Style
The design system for TindaTrack is built on the philosophy of **Monolith Craft**: a professional, high-density aesthetic that prioritizes speed, reliability, and precision. It is designed for the sari-sari store owner who requires a business tool that feels robust and institutional rather than playful.

The visual direction combines **Minimalism** with **High-Contrast** elements to ensure legibility in varying lighting conditions—from bright outdoor stalls to dimly lit shop interiors. The interface avoids unnecessary decoration, using structural rigidity and clear typographic hierarchy to guide the user through rapid sales entry and inventory management. The emotional response is one of "calculated efficiency"—a tool that works as hard as the person using it.

## Colors
The palette is monochromatic at its core, utilizing a range of slates and grays to create a "monolith" feel. **Emerald Green (#059669)** serves as the primary action color, chosen for its psychological association with profit, growth, and "go" signals in a retail context.

- **Primary:** Reserved for "Complete Sale," "Add Item," and high-value success states.
- **Secondary:** A deep Navy/Slate used for headers and primary navigation to provide a grounded, structural frame.
- **Semantic Colors:** Strict adherence to traffic-light logic for inventory status (In Stock, Low Stock, Out of Stock) to allow for instant peripheral recognition of store health.
- **Neutral:** High-contrast backgrounds (White) and structural borders (Light Gray) maintain data density without visual clutter.

## Typography
**Inter** is utilized across all levels to provide a neutral, highly legible, and "system-like" appearance.

The system introduces a **Display-Price** level specifically for the Calculator and Total Sales screens—oversized and bolded to prevent errors during transactions. **Label-Caps** are used for metadata like "STOCK STATUS" or "SKU" to differentiate static labels from dynamic user data. All numeric data should use tabular figures where possible to ensure that decimals and digits align perfectly in lists and reports.

## Layout & Spacing
This design system follows a **Fixed-Width Mobile** philosophy with a focus on thumb-zone optimization.

- **Grid:** A 4-column layout for mobile is used, with a strict 16px (1rem) margin.
- **Data Density:** Vertical spacing is tight (8px between related items) to maximize the amount of information visible on screen without scrolling, essential for comparing inventory or reviewing long receipts.
- **Keypad Layout:** The numeric keypad on the Home screen utilizes a custom grid with 1px borders to mimic a physical calculator, ensuring touch targets are no smaller than 48px in height.

## Elevation & Depth
In line with the Monolith Craft aesthetic, depth is communicated through **Tonal Layering** and **Crisp Outlines** rather than soft shadows.

- **Surface Tiers:** The main background is white. Secondary containers (like card backgrounds or "Quick Entry" sections) use a subtle tonal shift to Slate-50.
- **Borders:** Instead of heavy shadows, elements are defined by 1px solid borders in Slate-200.
- **Active State:** When an element is pressed, it should shift to a slightly darker tonal background (Slate-100) to provide immediate tactile feedback.
- **Floating Actions:** The only use of shadow is a single, low-blur "High-Contrast" shadow for the Bottom Navigation Bar to indicate it sits above the scrollable content.

## Shapes
Following the user request, the system uses **rounded-lg (0.5rem)** for primary components. This provides a subtle "modern tool" feel while maintaining enough structural rigidity to look professional.

- **Standard Components:** Buttons, Input fields, and Cards use the 8px radius.
- **Status Chips:** Use a full pill-shape (999px) to distinguish them from interactive buttons.
- **Keypad Buttons:** Use a smaller 4px radius to maximize the clickable surface area within the grid.

## Components
- **Buttons:** Primary buttons are solid Emerald Green with white text. Secondary buttons are outlined in Slate-200.
- **The Smart Keypad:** The central component of the app. It should feel mechanical. High-contrast numbers, 1px dividers, and haptic feedback on tap.
- **Inventory Cards:** Dense horizontal layouts. Product image on the left (small), Title and Price in the center, and Stock Status + Quick-Add (+1) on the right.
- **Input Fields:** Labeled internally with small caps. Use a solid 1px border that thickens to 2px Emerald Green on focus.
- **Navigation Bar:** Persistent at the bottom. Use solid icons when active and outlined icons when inactive. No text labels are needed if the iconography is distinct (Home, Box, Receipt, Chart).
- **Data Tables:** Used in Transactions and Analytics. Row-based with alternating subtle backgrounds to assist eye-tracking across price columns.
