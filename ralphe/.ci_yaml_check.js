const fs = require('fs');
// Very basic manual yaml validation since js-yaml might not be available
const content = fs.readFileSync('.github/workflows/cd-deploy.yml', 'utf8');
const lines = content.split('\n');
for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes('||') && !lines[i].includes('${{') && !lines[i].match(/run:.*\|\|/)) {
        console.log(`Suspicious line ${i + 1}: ${lines[i]}`);
    }
}
console.log('Done scanning.');
