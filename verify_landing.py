import re

with open(r'c:\Users\taufi\Downloads\bukupink-app\index.html', 'r', encoding='utf-8') as f:
    c = f.read()

scripts = re.findall(r'<script.*?>([\s\S]*?)<\/script>', c)
print(f'Total script tags: {len(scripts)}')
for i, s in enumerate(scripts):
    if s.count('{') != s.count('}'):
        print(f'Error in script {i}: {s.count("{")} vs {s.count("}")}')

assert 'id="screen-landing"' in c, 'screen-landing missing'
assert 'id="screen-onboarding"' in c, 'screen-onboarding missing'
assert 'id="screen-dashboard"' in c, 'screen-dashboard missing'
assert 'showLandingScreen' in c, 'showLandingScreen missing'
assert 'previewLandingPhase' in c, 'previewLandingPhase missing'
assert 'toggleFaq' in c, 'toggleFaq missing'
assert 'btn-lang-land-ms' in c, 'btn-lang-land-ms missing'

print('All landing page integrity tests passed perfectly!')
