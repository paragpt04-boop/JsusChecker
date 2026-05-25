with open('android/app/build.gradle', 'r') as f:
    content = f.read()

fix = """
configurations.all {
    resolutionStrategy {
        force 'org.jetbrains.kotlin:kotlin-stdlib:1.8.22'
        force 'org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.8.22'
        force 'org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.22'
    }
}
"""
if 'resolutionStrategy' not in content:
    content += fix

with open('android/app/build.gradle', 'w') as f:
    f.write(content)
print("Gradle fixed!")
