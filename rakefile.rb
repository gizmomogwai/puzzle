desc 'build'
task :build do
  sh "dub build -b release"
end

desc 'scramble_all'
scramble_all = task :scramble_all

desc 'unscramble_all'
unscramble_all = task :unscramble_all

Dir.glob("data/*_medium.*").each do |input|
  scrambled_output = "out/#{File.basename(input)}.scrambled.png"
  unscrambled_output = "#{scrambled_output}.unscrambled.png"

  desc scrambled_output
  t = task scrambled_output do
    sh "./puzzle scramble #{input}"
  end
  scramble_all.enhance([t])

  desc unscrambled_output
  t = task unscrambled_output do
    sh "./puzzle unscramble #{scrambled_output}"
  end
  unscramble_all.enhance([t])
end
