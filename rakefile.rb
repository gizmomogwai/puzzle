desc 'build'
task :build do
  sh "dub build -b release"
end

desc 'scramble_all'
scramble_all = task :scramble_all

desc 'unscramble_all'
unscramble_all = task :unscramble_all

directory "out"

Dir.glob("data/*_medium.*").each do |input|
  scrambled_output = "out/#{File.basename(input)}.scrambled.png"
  unscrambled_output = "#{scrambled_output}.unscrambled.png"

  desc scrambled_output
  t = task scrambled_output => "out" do
    sh "./puzzle scramble #{input}"
  end
  scramble_all.enhance([t])

  desc unscrambled_output
  t = task unscrambled_output => "out" do
    start = Time.now
    sh "gtime --verbose ./puzzle unscramble #{scrambled_output}"
    puts "took #{Time.now - start}"
    #start = Time.now
    #sh "gtime --verbose ./puzzle unscrambleP #{scrambled_output}"
    #puts "took #{Time.now - start}"
  end
  unscramble_all.enhance([t])
end
