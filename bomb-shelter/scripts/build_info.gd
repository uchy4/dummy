class_name BuildInfo
## Which CI build this binary came from. CI rewrites the 0 with the GitHub
## run number just before export; 0 means a local dev build (updater stays
## quiet so editors never see update prompts).

const BUILD := 0
